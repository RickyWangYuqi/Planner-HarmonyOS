// 提取并执行真实 TaskEditor 业务方法与 PlanerEngine；仅在内存中验证表单提交，不访问设备或用户数据。
// ArkUI 动画、@Watch、定时器和窗口几何使用可控环境；不验证组件渲染、真实触摸或系统键盘。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const project = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
const candidates = [process.env.TYPESCRIPT_PATH, 'typescript', path.join(project, '../Planer/node_modules/typescript'),
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'];
let ts;
for (const candidate of candidates.filter(Boolean)) {
  try { ts = require(candidate); break; } catch { /* 使用已有工具链，不下载依赖。 */ }
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向现有 TypeScript 模块。');

function transpile(source, filename) {
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, reportDiagnostics: true,
    fileName: filename
  });
  const errors = (output.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(ts.formatDiagnosticsWithColorAndContext(errors, {
    getCurrentDirectory: () => project, getCanonicalFileName: file => file, getNewLine: () => '\n'
  }));
  return output.outputText;
}

const modules = new Map();
function loadModel(name) {
  if (modules.has(name)) return modules.get(name);
  const filename = path.join(project, 'entry/src/main/ets/model', `${name}.ets`);
  const output = transpile(readFileSync(filename, 'utf8'), filename);
  const module = { exports: {} };
  vm.runInThisContext(`(function(require,module,exports){${output}\n})`, { filename })(
    request => loadModel(path.basename(request)), module, module.exports);
  modules.set(name, module.exports);
  return module.exports;
}
const { AppAction, AppData, Task } = loadModel('PlanerModel');
const { freshData, reduce, addDays, normalizeData } = loadModel('PlanerEngine');

const editorPath = path.join(project, 'entry/src/main/ets/components/TaskEditor.ets');
const editorSource = readFileSync(editorPath, 'utf8');
const classStart = editorSource.indexOf('@Component');
const firstBuilder = editorSource.indexOf('  @Builder');
if (classStart < 0 || firstBuilder <= classStart) throw new Error('TaskEditor 结构已变化，请更新测试提取边界。');
// 不复制业务实现：去掉 ArkUI 装饰器，保留字段、生命周期和所有构建方法之前的真实方法。
const watchBindings = Array.from(editorSource.matchAll(/@Watch\('([^']+)'\)\s+private\s+(\w+)/g),
  match => ({ method: match[1], field: match[2] }));
let editorClass = editorSource.slice(classStart, firstBuilder)
  .replace('@Component', '').replace('export struct TaskEditor', 'class TaskEditor')
  .replace(/@(?:Prop|State)\s+/g, '').replace(/@Watch\('[^']+'\)\s*/g, '');

// 提取真实 Builder 的块状箭头回调，仅依赖调用标记，不在测试中复制删除态规则。
function viewCallback(marker, signature) {
  const markerIndex = editorSource.indexOf(marker);
  const signatureIndex = markerIndex < 0 ? -1 : editorSource.indexOf(signature, markerIndex);
  if (signatureIndex < 0) throw new Error(`找不到视图回调：${marker}`);
  const bodyStart = signatureIndex + signature.length;
  let depth = 1;
  for (let index = bodyStart; index < editorSource.length; index++) {
    if (editorSource[index] === '{') depth++;
    if (editorSource[index] === '}' && --depth === 0) return editorSource.slice(bodyStart, index);
  }
  throw new Error(`视图回调未闭合：${marker}`);
}
const dateBuilder = editorSource.slice(editorSource.indexOf('  private dateFieldButton('), editorSource.indexOf('  private dateSectionBody('));
const dateTextExpression = dateBuilder.match(/\bText\((.*?)\)\.fontSize\(14\)/)?.[1];
const dateAccessExpression = dateBuilder.match(/\.accessibilityText\((.*?)\)\s*\n/)?.[1];
if (!dateTextExpression || !dateAccessExpression) throw new Error('缺少日期按钮的真实文案表达式');
const longPressGroup = viewCallback('private groupLabelButton(', '.onAction(() => {');
const cancelEditor = viewCallback(".id('task-cancel')", '.onClick(() => {');
const closeEditor = viewCallback("label: '取消编辑'", 'onTap: () => {');
const deleteTask = viewCallback(".id('task-delete')", '.onClick(() => {');
// 取消创建动作位于 Builder 内，单独提取真实按钮回调，避免测试自行重写取消规则。
const cancelCreate = viewCallback('private groupCancelButton(', '.onClick(() => {');
const createGroupFromView = viewCallback('private groupCreateButton(', '.onClick(() => {');
const submitFromView = viewCallback(".id('task-submit')", '.onClick(() => {');
editorClass += `
  getUIContext() {
    return {
      animateTo: (options, callback) => {
        recordAnimation();
        callback();
        if (options.onFinish) {
          if (this.testAnimationFinishes) this.testAnimationFinishes.push(options.onFinish);
          else options.onFinish();
        }
      },
      getFocusController: () => ({ clearFocus: () => { this.testClearFocusCalls = (this.testClearFocusCalls || 0) + 1; } }),
      getHostContext: () => this.testHostContext,
      px2vp: value => value / (this.testDensity || 1),
      getFrameNodeById: id => this.testNodes?.get(id) || null
    };
  }
  dateLabelFromView(field) { return ${dateTextExpression}; }
  dateAccessibilityFromView(field, title) { return ${dateAccessExpression}; }
  cancelCreateFromView() { ${cancelCreate} }
  createGroupFromView() { ${createGroupFromView} }
  submitFromView() { ${submitFromView} }
  longPressGroupFromView(group) { ${longPressGroup} }
  cancelEditorFromView() { ${cancelEditor} }
  closeEditorFromView() { ${closeEditor} }
  deleteTaskFromView() { ${deleteTask} }
}
globalThis.Editor = TaskEditor;
`;
// 假时钟保留真实 setInterval/clearInterval 语义；测试推进时间，不等待或遗留宿主定时器。
const timers = {
  now: 0, sequence: 0, scheduled: new Map(),
  start(callback, interval, repeat = true) {
    const id = ++this.sequence;
    this.scheduled.set(id, { id, callback, interval, repeat, due: this.now + interval });
    return id;
  },
  stop(id) { this.scheduled.delete(id); },
  advance(milliseconds) {
    const target = this.now + milliseconds;
    while (true) {
      const next = [...this.scheduled.values()].filter(timer => timer.due <= target)
        .sort((a, b) => a.due - b.due)[0];
      if (!next) break;
      this.now = next.due;
      if (next.repeat) next.due += next.interval;
      else this.scheduled.delete(next.id);
      next.callback();
    }
    this.now = target;
  }
};
// 加载真实反馈状态机，覆盖丢失 Up 后打开面板以及点击中关闭表单的生命周期。
const appearanceSource = readFileSync(path.join(project, 'entry/src/main/ets/theme/Appearance.ets'), 'utf8');
const feedbackStart = appearanceSource.indexOf('export class ButtonFeedback');
const feedbackEnd = appearanceSource.indexOf('const controlMaterials:', feedbackStart);
if (feedbackStart < 0 || feedbackEnd < 0) throw new Error('缺少真实 ButtonFeedback');
const feedbackSource = appearanceSource.slice(feedbackStart, feedbackEnd).replace('export class', 'class');
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
let animationCalls = 0;
let fullUiSupported = true;
const editorContext = vm.createContext({
  AppAction, AppData, Task, addDays, TouchType,
  canIUse: capability => capability === 'SystemCapability.ArkUI.ArkUI.Full' && fullUiSupported,
  Palette: class {},
  Scroller: class {
    scrollCalls = [];
    scrollToCalls = [];
    offsetY = 0;
    scrollBy(x, y) { this.scrollCalls.push({ x, y }); }
    offset() { return { xOffset: 0, yOffset: this.offsetY }; }
    scrollTo(options) { this.scrollToCalls.push(options); }
  },
  TextAreaController: class { stopCalls = 0; stopEditing() { this.stopCalls++; } },
  TextInputController: class { stopCalls = 0; stopEditing() { this.stopCalls++; } },
  Curve: { EaseInOut: 'ease-in-out' },
  window: {
    AvoidAreaType: { TYPE_KEYBOARD: 'keyboard' },
    getLastWindow: context => context.pending || Promise.resolve(context.editorWindow)
  },
  console,
  Motion: { quick: () => ({}), spring: () => ({}) },
  setInterval: (callback, interval) => timers.start(callback, interval),
  clearInterval: id => timers.stop(id),
  setTimeout: (callback, delay) => timers.start(callback, delay, false),
  clearTimeout: id => timers.stop(id),
  recordAnimation: () => { animationCalls++; }
});
vm.runInContext(transpile(feedbackSource + editorClass, editorPath), editorContext, { filename: editorPath });
const Editor = editorContext.Editor;
let passed = 0;
function assert(condition, message) {
  if (!condition) throw new Error(message);
  passed++;
  console.log(`✓ ${message}`);
}

function initialData() {
  const data = freshData();
  data.currentDate = '2026-10-15';
  data.settings.showGroups = true;
  return data;
}
function addTask(data, text, group, section = 'today') {
  const action = new AppAction('ADD_TASK');
  action.text = text;
  action.group = group;
  action.section = section;
  if (section === 'future') action.dueDate = '2026-10-17';
  return reduce(data, action);
}
function createEditor(data = initialData(), options = {}) {
  const editor = new Editor();
  // 按源码装饰器安装同步观察器；同值赋值不触发，覆盖取消动作对 watcher 的真实依赖。
  for (const binding of watchBindings) {
    let value = editor[binding.field];
    Object.defineProperty(editor, binding.field, {
      configurable: true, enumerable: true,
      get: () => value,
      set(next) {
        if (Object.is(value, next)) return;
        value = next;
        editor[binding.method](binding.field);
      }
    });
  }
  Object.assign(editor, { data }, options);
  const actions = [];
  let closes = 0;
  editor.onAction = action => {
    actions.push(action);
    editor.data = reduce(editor.data, action);
  };
  editor.onClose = () => { closes++; };
  editor.aboutToAppear();
  return { editor, actions, closes: () => closes };
}
function inputGroup(editor, name) {
  editor.openGroupForm();
  editor.groupName = name;
}
function editing(group = '原分组', settings = true) {
  const data = addTask(initialData(), '原日程', group);
  data.settings.showGroups = settings;
  return createEditor(data, { mode: 'edit', task: data.todayTasks[0] });
}

console.log('1) 未局部确认的新组名随主添加保存');
{
  const { editor, actions, closes } = createEditor();
  editor.content = '  直接提交  ';
  inputGroup(editor, '  工作  ');
  editor.submit();
  assert(editor.data.todayTasks[0].group === '工作', '主添加采纳并去除待确认分组名首尾空白');
  assert(editor.data.groups.length === 1 && editor.data.groups[0] === '工作', '新组目录随真实引擎保存');
  assert(editor.data.todayTasks[0].text === '直接提交', '日程正文仍按原规则去除首尾空白');
  assert(actions.length === 1 && closes() === 1, '直接提交只产生一个动作并关闭一次');
  assert(normalizeData(JSON.parse(JSON.stringify(editor.data))).todayTasks[0].group === '工作', '重新读取 JSON 后保留直接提交的分组');
}

console.log('2) 编辑已有日程直接采用新组名');
{
  const { editor } = editing();
  const originalId = editor.task.id;
  editor.content = '编辑后的日程';
  inputGroup(editor, '新分组');
  editor.submit();
  assert(editor.data.todayTasks.length === 1 && editor.data.todayTasks[0].id === originalId && editor.data.todayTasks[0].group === '新分组', '编辑只更新原任务并采用待确认新组');
  assert(editor.data.groups.includes('原分组') && editor.data.groups.includes('新分组'), '改组保留原空组目录并登记新组');
}

console.log('3) 局部确认及同名分组复用');
{
  const { editor, actions } = createEditor();
  editor.content = '局部创建';
  inputGroup(editor, '学习');
  editor.createGroup();
  assert(actions.length === 0 && editor.data.groups.length === 0, '局部创建仅产生草稿，不提前写入数据');
  editor.submit();
  assert(editor.data.todayTasks[0].group === '学习', '局部确认后的主提交正常保存所选组');
}
{
  const data = addTask(initialData(), '已有任务', '工作');
  const { editor } = createEditor(data);
  editor.content = '同名复用';
  inputGroup(editor, ' 工作 ');
  editor.submit();
  assert(editor.data.groups.filter(group => group === '工作').length === 1, '直接提交同名组不创建重复目录');
  assert(editor.data.todayTasks[1].group === '工作', '同名组正确用于新任务');
}

console.log('4) 空白名称与取消局部创建');
{
  const { editor } = editing();
  inputGroup(editor, '   ');
  editor.submit();
  assert(editor.data.todayTasks[0].group === '原分组', '空白待确认名称不清除编辑前分组');
}
{
  const { editor } = createEditor();
  editor.content = '无分组任务';
  inputGroup(editor, '  ');
  editor.submit();
  assert(editor.data.todayTasks[0].group === null && editor.data.groups.length === 0, '空白组名新增仍是未分组且不登记空名称');
}
{
  const { editor } = editing();
  inputGroup(editor, '已取消的新组');
  editor.cancelCreateFromView();
  editor.submit();
  assert(editor.data.todayTasks[0].group === '原分组', '点击真实取消创建回调后保存保持原分组');
  assert(!editor.data.groups.includes('已取消的新组'), '取消创建遗留的输入文本不会落盘');
}

console.log('5) 取消整张表单不提交草稿');
{
  const { editor, actions, closes } = createEditor();
  const before = JSON.stringify(editor.data);
  editor.content = '未保存日程';
  inputGroup(editor, '确认过的草稿');
  editor.createGroup();
  inputGroup(editor, '尚未确认的草稿');
  editor.onClose();
  assert(actions.length === 0 && JSON.stringify(editor.data) === before, '取消整表不保存任何日程或草稿分组');
  assert(closes() === 1, '取消整表只关闭一次');
}

console.log('6) 已选标签再次点击可取消，多个草稿仅保存实际所选');
{
  const { editor } = createEditor();
  editor.content = '取消分组选择';
  inputGroup(editor, '刚创建');
  editor.createGroup();
  editor.pickGroup('刚创建');
  editor.submit();
  assert(editor.data.todayTasks[0].group === null, '再次点击已选组后按未分组保存');
  assert(!editor.data.groups.includes('刚创建'), '未用于任务的草稿不登记到持久目录');
}
{
  const { editor } = createEditor();
  editor.content = '多个草稿';
  inputGroup(editor, '草稿A');
  editor.createGroup();
  inputGroup(editor, '草稿B');
  editor.createGroup();
  editor.submit();
  assert(editor.data.todayTasks[0].group === '草稿B', '多个草稿提交最后选中的分组');
  assert(editor.data.groups.includes('草稿B') && !editor.data.groups.includes('草稿A'), '不额外持久化未选中的草稿');
}

console.log('7) 隐藏分组与移动模式不受待确认输入影响');
{
  const { editor, actions } = editing('隐藏组', false);
  editor.content = '只改正文';
  inputGroup(editor, '不应创建');
  editor.submit();
  assert(editor.data.todayTasks[0].group === '隐藏组' && actions[0].group === undefined, '关闭分组显示后编辑保留隐藏归属');
  assert(!editor.data.groups.includes('不应创建'), '隐藏分组时不隐式确认名称');
}
{
  const data = addTask(addTask(initialData(), '待移动', '原组'), '目标既有任务', '目标组', 'future');
  const { editor } = createEditor(data, { mode: 'move', section: 'future', task: data.todayTasks[0], targetIndex: 0, targetGroup: '目标组' });
  inputGroup(editor, '不应覆盖移动落点');
  editor.dueDate = '2026-10-18';
  editor.submit();
  assert(editor.data.todayTasks.length === 0 && editor.data.futureTasks[0].group === '目标组', '移动使用明确目标组及目标位置');
  assert(editor.data.futureTasks[0].dueDate === '2026-10-18', '移动表单继续提交截止日期');
  assert(!editor.data.groups.includes('不应覆盖移动落点'), '移动模式不确认隐藏的分组输入');
}
{
  const data = addTask(initialData(), '保留分组移动', '原组');
  const { editor } = createEditor(data, { mode: 'move', section: 'future', task: data.todayTasks[0], targetGroup: undefined });
  editor.submit();
  assert(editor.data.futureTasks[0].group === '原组', '移动目标组undefined保留原归属');
}
{
  const data = addTask(initialData(), '移入未分组', '原组');
  const { editor } = createEditor(data, { mode: 'move', section: 'future', task: data.todayTasks[0], targetGroup: null });
  editor.submit();
  assert(editor.data.futureTasks[0].group === null, '移动目标组null明确取消原归属');
}

console.log('8) 无效表单不提前登记分组');
{
  const { editor, actions, closes } = createEditor();
  inputGroup(editor, '待确认');
  editor.submit();
  assert(actions.length === 0 && closes() === 0 && editor.data.groups.length === 0, '正文为空时不提交、不关闭、不保存分组');
}
{
  const { editor, actions } = createEditor(initialData(), { section: 'future' });
  editor.content = '缺少截止日期';
  inputGroup(editor, '未来分组');
  editor.submit();
  assert(actions.length === 0 && editor.data.groups.length === 0, '未来缺少截止日期时不提前保存组名');
  editor.dueDate = '2026-10-17';
  editor.submit();
  assert(editor.data.futureTasks[0].group === '未来分组', '补齐未来截止日期后直接保存待确认分组');
}

console.log('9) 长按删除态使用单个定时器，小角度交替且不改数据');
{
  const { editor, actions } = editing();
  editor.longPressGroupFromView('原分组');
  const firstTimer = editor.deleteShakeTimer;
  const initialAngle = editor.deleteShakeAngle;
  assert(editor.deleteMode === '原分组' && timers.scheduled.size === 1, '真实长按回调经源码 Watch 启动一个摇摆定时器');
  timers.advance(240);
  assert(initialAngle * editor.deleteShakeAngle < 0 && Math.abs(editor.deleteShakeAngle) <= 2,
    '推进真实间隔后角度反向且保持小于两度');
  editor.longPressGroupFromView('原分组');
  assert(editor.deleteShakeTimer === firstTimer && timers.scheduled.size === 1, '重复长按同一标签不会叠加定时器');
  editor.longPressGroupFromView('另一分组');
  assert(!timers.scheduled.has(firstTimer) && timers.scheduled.size === 1, '切换待删除标签清理旧定时器并只保留一个');
  assert(actions.length === 0, '长按与摇摆本身不派发数据动作');
  editor.aboutToDisappear();
}

console.log('10) 取消删除态与改选分组停止摇摆');
{
  const { editor, actions } = editing();
  editor.longPressGroupFromView('原分组');
  editor.pickGroup('原分组');
  const stoppedAt = animationCalls;
  timers.advance(1440);
  assert(editor.deleteMode === '' && editor.selectedGroup === '原分组', '再次点击待删除标签仅取消删除，不改变原选择');
  assert(timers.scheduled.size === 0 && editor.deleteShakeAngle === 0 && animationCalls === stoppedAt,
    '取消删除后六个间隔内没有残留动画回调');
  editor.longPressGroupFromView('原分组');
  editor.pickGroup('另一分组');
  assert(editor.selectedGroup === '另一分组' && timers.scheduled.size === 0 && editor.deleteShakeAngle === 0,
    '改选其他组正常更新选择并停止摇摆');
  editor.longPressGroupFromView('');
  assert(editor.deleteMode === '' && timers.scheduled.size === 0 && actions.length === 0, '未分组标签不能进入删除摇摆或派发动作');
}

console.log('11) 新建与确认分组同步退出删除态');
{
  const { editor, actions } = editing();
  editor.longPressGroupFromView('原分组');
  editor.openGroupForm();
  assert(editor.creatingGroup && editor.deleteMode === '' && timers.scheduled.size === 0, '展开新建组表单清理已有摇摆');
  editor.groupName = '新增组';
  editor.longPressGroupFromView('原分组');
  editor.createGroup();
  assert(editor.selectedGroup === '新增组' && timers.scheduled.size === 0 && editor.deleteShakeAngle === 0,
    '确认新组时停止摇摆并保留既有创建选择规则');
  assert(actions.length === 0, '新建草稿和动画切换不提前派发持久化动作');
}

console.log('12) 保存停止定时器且只提交一次');
{
  const { editor, actions, closes } = editing();
  editor.longPressGroupFromView('原分组');
  editor.submit();
  const stoppedAt = animationCalls;
  timers.advance(1440);
  assert(timers.scheduled.size === 0 && editor.deleteShakeAngle === 0 && animationCalls === stoppedAt,
    '保存后清空摇摆定时器与角度，时间推进不继续动画');
  assert(actions.length === 1 && actions[0].type === 'EDIT_TASK' && closes() === 1,
    '摇摆状态下保存仅编辑一次、关闭一次');
  assert(editor.data.todayTasks[0].group === '原分组', '清理动画不误删或改写已选分组');
}

console.log('13) 底部取消与标题关闭立即清理，不等待组件销毁');
{
  const { editor, actions, closes } = editing();
  editor.longPressGroupFromView('原分组');
  editor.cancelEditorFromView();
  const stoppedAt = animationCalls;
  timers.advance(1440);
  assert(timers.scheduled.size === 0 && editor.deleteShakeAngle === 0 && animationCalls === stoppedAt,
    '真实底部取消按钮在消失动画前即停止所有摇摆回调');
  assert(actions.length === 0 && closes() === 1, '底部取消没有数据动作或重复关闭');
}
{
  const { editor, actions, closes } = editing();
  editor.longPressGroupFromView('原分组');
  editor.closeEditorFromView();
  const stoppedAt = animationCalls;
  timers.advance(1440);
  assert(timers.scheduled.size === 0 && editor.deleteShakeAngle === 0 && animationCalls === stoppedAt,
    '真实标题关闭按钮在组件销毁前即停止所有摇摆回调');
  assert(actions.length === 0 && closes() === 1, '标题关闭没有数据动作或重复关闭');
}

console.log('14) 删除已有分组与草稿均停止摇摆，不重复删除');
{
  const data = addTask(addTask(initialData(), '当日组内日程', '工作'), '未来组内日程', '工作', 'future');
  const { editor, actions } = createEditor(data);
  editor.longPressGroupFromView('工作');
  const queuedCallback = timers.scheduled.get(editor.deleteShakeTimer).callback;
  editor.removeGroup('工作');
  timers.advance(1440);
  queuedCallback();
  assert(timers.scheduled.size === 0 && editor.deleteShakeAngle === 0 && editor.deleteMode === '',
    '移除已有分组清理定时器，迟到的回调也不能重启');
  assert(actions.length === 2 && actions.every(action => action.type === 'DELETE_GROUP') &&
    actions[0].section === 'today' && actions[1].section === 'future', '已有分组仅按既有规则对两分区各删除一次');
  assert(editor.data.todayTasks.length === 1 && editor.data.futureTasks.length === 1 &&
    editor.data.todayTasks[0].group === null && editor.data.futureTasks[0].group === null,
    '删除分组保留两区任务并移入未分组');
}
{
  const { editor, actions } = createEditor();
  inputGroup(editor, '草稿组');
  editor.createGroup();
  editor.longPressGroupFromView('草稿组');
  editor.removeGroup('草稿组');
  timers.advance(1440);
  assert(timers.scheduled.size === 0 && editor.deleteShakeAngle === 0 && !editor.draftGroups.includes('草稿组'),
    '删除草稿标签停止摇摆并移除本次草稿');
  assert(actions.length === 0 && editor.data.groups.length === 0, '删除未落盘草稿不派发数据动作');
}

console.log('15) 系统返回或下滑关闭触发生命周期清理');
{
  const { editor, actions, closes } = editing();
  editor.longPressGroupFromView('原分组');
  const queuedCallback = timers.scheduled.get(editor.deleteShakeTimer).callback;
  editor.aboutToDisappear();
  const stoppedAt = animationCalls;
  timers.advance(1440);
  assert(timers.scheduled.size === 0 && editor.deleteShakeAngle === 0 && animationCalls === stoppedAt,
    '未经过表单按钮的组件消失也清空全部摇摆回调');
  queuedCallback();
  editor.deleteMode = '销毁后异步更新';
  editor.aboutToDisappear();
  assert(timers.scheduled.size === 0 && editor.deleteShakeAngle === 0 && !editor.editorActive,
    '消失后的迟到回调、状态更新与重复清理不能重新启动摇摆');
  assert(actions.length === 0 && closes() === 0, '生命周期清理不会提交数据或再次调用关闭');
}

console.log('16) 删除日程确认期间也停止分组摇摆');
{
  const { editor, actions, closes } = editing();
  let deleteRequests = 0;
  editor.onDelete = () => { deleteRequests++; };
  editor.longPressGroupFromView('原分组');
  editor.deleteTaskFromView();
  const stoppedAt = animationCalls;
  timers.advance(1440);
  assert(timers.scheduled.size === 0 && editor.deleteShakeAngle === 0 && animationCalls === stoppedAt,
    '真实删除日程按钮在进入确认流程前停止摇摆');
  assert(deleteRequests === 1 && actions.length === 0 && closes() === 0,
    '删除日程只请求确认一次，组件不提前删除数据或关闭');
}

// 模拟窗口只提供官方接口契约；几何计算与监听注销均执行真实编辑器方法。
function keyboardWindow(height = 2400, keyboardHeight = 600) {
  return {
    height, keyboardHeight, listeners: new Map(), onCalls: 0, offCallbacks: [],
    on(event, callback) { this.onCalls++; this.listeners.set(event, callback); },
    off(event, callback) {
      this.offCallbacks.push(callback);
      if (this.listeners.get(event) === callback) this.listeners.delete(event);
    },
    getWindowProperties() { return { windowRect: { height: this.height } }; },
    getWindowAvoidArea() { return { bottomRect: { height: this.keyboardHeight } }; }
  };
}
function rootArea(y, height) { return { globalPosition: { y }, height }; }

console.log('17) 已打开键盘初始化、密度换算与弹层局部重叠');
{
  const editorWindow = keyboardWindow();
  const { editor, actions } = createEditor(initialData(), {
    testHostContext: { editorWindow }, testDensity: 3
  });
  editor.updateEditorArea(rootArea(40, 720));
  await new Promise(resolve => setImmediate(resolve));
  assert(editorWindow.onCalls === 1 && editor.keyboardInset === 160,
    '初始键盘已打开时使用真实窗口像素换算，只填补编辑器与键盘重叠的160vp');
  editorWindow.listeners.get('keyboardHeightChange')(900);
  assert(editor.keyboardInset === 260, '键盘高度变化重新计算编辑器局部内边距');
  editor.updateEditorArea(rootArea(40, 510));
  assert(editor.keyboardInset === 50, '弹层位置或尺寸变化同步更新重叠量');
  editor.updateEditorArea(rootArea(40, 400));
  assert(editor.keyboardInset === 0, '编辑器底部高于键盘时不产生负数内边距或多余避让');
  editorWindow.listeners.get('keyboardHeightChange')(0);
  assert(editor.keyboardInset === 0 && actions.length === 0, '收起键盘恢复原布局且不派发业务动作');
  editor.aboutToDisappear();
}

console.log('18) 关闭注销同一监听、忽略迟到回调与异步窗口');
{
  const editorWindow = keyboardWindow();
  const { editor, actions, closes } = createEditor(initialData(), {
    testHostContext: { editorWindow }, testDensity: 3
  });
  editor.updateEditorArea(rootArea(40, 720));
  await new Promise(resolve => setImmediate(resolve));
  const queuedCallback = editorWindow.listeners.get('keyboardHeightChange');
  editor.cancelEditorFromView();
  editor.aboutToDisappear();
  editor.aboutToDisappear();
  queuedCallback(900);
  assert(editorWindow.offCallbacks.length === 1 && editorWindow.offCallbacks[0] === queuedCallback &&
    editorWindow.listeners.size === 0, '关闭时使用注册时的同一个函数注销，重复清理不重复注销');
  assert(editor.keyboardInset === 0 && editor.keyboardHeightPx === 0 && !editor.editorWindow &&
    actions.length === 0 && closes() === 1, '关闭后的排队键盘事件不能恢复避让、提交数据或重复关闭');
}
{
  let resolveWindow;
  const pending = new Promise(resolve => { resolveWindow = resolve; });
  const editorWindow = keyboardWindow();
  const { editor } = createEditor(initialData(), { testHostContext: { pending }, testDensity: 3 });
  editor.aboutToDisappear();
  resolveWindow(editorWindow);
  await new Promise(resolve => setImmediate(resolve));
  assert(editorWindow.onCalls === 0 && !editor.editorWindow && editor.keyboardInset === 0,
    '窗口异步返回前已关闭编辑器时不注册监听，也不修改消失组件');
}

console.log('19) 聚焦输入仅滚动编辑器，位置vp与尺寸px正确换算');
{
  const { editor, actions } = createEditor(initialData(), { testDensity: 3 });
  let inputTop = 400;
  editor.testNodes = new Map([
    ['group-name', { getPositionToWindowWithTransform: () => ({ y: inputTop }), getMeasuredSize: () => ({ height: 132 }) }],
    ['task-editor-scroll', { getPositionToWindowWithTransform: () => ({ y: 100 }), getMeasuredSize: () => ({ height: 900 }) }]
  ]);
  editor.focusInput('group-name');
  assert(editor.scroller.scrollCalls.length === 1 && editor.scroller.scrollCalls[0].y === 52,
    '输入框底部超出缩小滚动区时只滚动所需52vp，并保留8vp间距');
  inputTop = 140;
  editor.ensureFocusedInputVisible();
  assert(editor.scroller.scrollCalls.length === 1, '输入框完全可见时不额外滚动');
  inputTop = 90;
  editor.ensureFocusedInputVisible();
  assert(editor.scroller.scrollCalls[1].y === -18, '输入框位于滚动区上方时按实际差值向上回滚');
  editor.blurInput('group-name');
  editor.ensureFocusedInputVisible();
  editor.aboutToDisappear();
  editor.ensureFocusedInputVisible();
  assert(editor.scroller.scrollCalls.length === 2 && editor.focusedInput === '' && actions.length === 0,
    '失焦或关闭后不再自动滚动，焦点保持逻辑不产生业务动作');
}

console.log('20) 半模态实际窗口位置优先于内容区回调位置');
{
  let rootTop = 300;
  const editorWindow = keyboardWindow();
  const root = { getPositionToWindow: () => ({ y: 0 }), getPositionToWindowWithTransform: () => ({ y: rootTop }), getMeasuredSize: () => ({ height: 1440 }) };
  const { editor } = createEditor(initialData(), {
    testHostContext: { editorWindow }, testDensity: 3, testNodes: new Map([['task-editor-root', root]])
  });
  editor.updateEditorArea(rootArea(0, 480));
  await new Promise(resolve => setImmediate(resolve));
  assert(editor.editorBottomVp === 780 && editor.keyboardInset === 180,
    '半模态根节点实际底边包含300vp窗口偏移，不采用缺少平移的内容区坐标');
  rootTop = 280;
  editorWindow.listeners.get('keyboardHeightChange')(600);
  assert(editor.editorBottomVp === 760 && editor.keyboardInset === 160,
    '键盘事件重新读取当前节点位置，无需等待内容区尺寸再次变化');
  editor.aboutToDisappear();
}

function dateNodes() {
  return new Map([
    ['task-due-date', { getPositionToWindowWithTransform: () => ({ y: 700 }) }],
    ['task-editor-scroll', { getPositionToWindowWithTransform: () => ({ y: 150 }), getMeasuredSize: () => ({ height: 1200 }) }]
  ]);
}

console.log('21) 缺少截止日期允许触发校验，阻止提交并平滑定位');
{
  const { editor, actions, closes } = createEditor(initialData(), { section: 'future', testNodes: dateNodes() });
  editor.content = '未选择截止日期';
  editor.scroller.offsetY = 60;
  assert(editor.canAttemptSubmit() && !editor.canSubmit(), '正文非空允许点击添加，但完整业务校验仍拒绝缺少截止日期');
  editor.submit();
  assert(actions.length === 0 && closes() === 0 && editor.dueDate === '' && editor.dueDateError.includes('请选择截止日期'),
    '缺少日期时明确提示、不自动填日期、不提交也不关闭');
  editor.submit();
  editor.editorViewportChanged();
  editor.editorViewportChanged();
  assert(timers.scheduled.size === 1 && editor.testClearFocusCalls === 1, '重复点击与连续布局刷新只保留一个定位定时器和一次失焦请求');
  timers.advance(100);
  assert(editor.scroller.scrollToCalls.length === 1 && editor.scroller.scrollToCalls[0].yOffset === 598 &&
    editor.scroller.scrollToCalls[0].animation.duration === 360,
    '布局稳定后根据当前offset和窗口坐标差平滑滚到截止日期区');
  editor.submit();
  timers.advance(400);
  assert(editor.scroller.scrollToCalls.length === 1 && timers.scheduled.size === 0 && !editor.dueDateScrollAnimating,
    '定位动画期间重复提交不重启动画，结束后没有残留定时器');
  editor.aboutToDisappear();
}

console.log('22) 无效日期与起止约束保留草稿，选择合法日期清错后正常提交');
{
  const { editor, actions, closes } = createEditor(initialData(), { section: 'future', testNodes: dateNodes() });
  editor.content = '日期校验恢复';
  editor.startDate = '2026-10-20';
  editor.dueDate = '2026-10-19';
  editor.submit();
  assert(actions.length === 0 && editor.dueDateError.includes('2026-10-20') && editor.dueDate === '2026-10-19',
    '截止早于起始时提示最早有效日期并保留原始草稿，不偷偷修正提交');
  editor.dueDate = '2027-02-30';
  editor.submit();
  assert(!editor.canSubmit() && actions.length === 0, '不存在的日历日期即使字符串晚于最早日期也不能提交');
  editor.pickDue('2026-10-21');
  assert(editor.dueDateError === '' && !editor.dueDateScrollPending && timers.scheduled.size === 0,
    '选择有效日期立即清除提示和尚未执行的定位');
  editor.submit();
  assert(actions.length === 1 && actions[0].type === 'ADD_TASK' && closes() === 1 &&
    editor.data.futureTasks[0].dueDate === '2026-10-21' && editor.data.futureTasks[0].startDate === '2026-10-20',
    '纠正日期后只提交一次，准确保留用户选择的起止日期');
  editor.aboutToDisappear();
}

console.log('23) 键盘收起与局部避让动画结束后才定位，不移动背景');
{
  const editorWindow = keyboardWindow();
  const finishes = [];
  const { editor, actions } = createEditor(initialData(), {
    section: 'future', testHostContext: { editorWindow }, testDensity: 3,
    testNodes: dateNodes(), testAnimationFinishes: finishes
  });
  editor.updateEditorArea(rootArea(40, 720));
  await new Promise(resolve => setImmediate(resolve));
  finishes.shift()();
  editor.content = '键盘中的待提交日程';
  editor.focusedInput = 'group-name';
  editor.submit();
  assert(editor.groupController.stopCalls === 1 && editor.contentController.stopCalls === 0 &&
    editor.focusedInput === '' && timers.scheduled.size === 0,
    '错误校验先停止当前输入编辑并清焦点，键盘仍可见时不启动定位');
  editorWindow.listeners.get('keyboardHeightChange')(0);
  timers.advance(500);
  assert(editor.scroller.scrollToCalls.length === 0 && editor.keyboardLayoutSettling && editor.dueDateScrollPending,
    '键盘高度已归零但表单避让动画未结束时继续等待');
  finishes.shift()();
  editor.editorViewportChanged();
  timers.advance(100);
  assert(editor.scroller.scrollToCalls.length === 1 && editor.keyboardInset === 0 && editor.editorBottomVp === 760 && actions.length === 0,
    '避让结束且布局稳定后仅滚动编辑器，不改根几何或业务数据');
  editor.aboutToDisappear();
  assert(timers.scheduled.size === 0, '关闭表单清理日期定位动画锁定时器');
}

console.log('24) 取消与空正文不产生迟到定位或业务动作');
{
  const { editor, actions, closes } = createEditor(initialData(), { section: 'future', testNodes: dateNodes() });
  editor.content = '即将取消';
  editor.submit();
  const queuedCallback = timers.scheduled.get(editor.dueDateScrollTimer).callback;
  editor.cancelEditorFromView();
  timers.advance(500);
  queuedCallback();
  assert(editor.scroller.scrollToCalls.length === 0 && timers.scheduled.size === 0 && actions.length === 0 && closes() === 1,
    '取消即时清理待定位请求，迟到回调也不能滚动、提交或重复关闭');
  editor.aboutToDisappear();
}
{
  const { editor, actions } = createEditor(initialData(), { section: 'future', testNodes: dateNodes() });
  editor.submit();
  assert(!editor.canAttemptSubmit() && editor.dueDateError === '' && timers.scheduled.size === 0 && actions.length === 0,
    '正文为空保持既有禁用规则，不抢先提示日期或定位');
  editor.aboutToDisappear();
}

console.log('25) 取消和选好日期会打断已经发出的原生定位动画');
{
  const { editor, actions, closes } = createEditor(initialData(), { section: 'future', testNodes: dateNodes() });
  editor.content = '动画中取消';
  editor.submit();
  timers.advance(100);
  editor.scroller.offsetY = 225;
  editor.cancelEditorFromView();
  const stop = editor.scroller.scrollToCalls[1];
  assert(editor.scroller.scrollToCalls.length === 2 && stop.animation === false && stop.yOffset === 225,
    '取消时向当前实际offset发出无动画滚动，打断已启动的原生定位');
  timers.advance(500);
  assert(timers.scheduled.size === 0 && !editor.dueDateScrollAnimating && actions.length === 0 && closes() === 1,
    '打断原生动画后清理全部JS状态，不产生迟到动作或重复关闭');
  editor.aboutToDisappear();
}
{
  const { editor } = createEditor(initialData(), { section: 'future', testNodes: dateNodes() });
  editor.content = '动画中选择日期';
  editor.submit();
  timers.advance(100);
  editor.scroller.offsetY = 310;
  editor.pickDue('2026-10-18');
  assert(editor.dueDateError === '' && editor.scroller.scrollToCalls[1].animation === false &&
    editor.scroller.scrollToCalls[1].yOffset === 310 && timers.scheduled.size === 0,
    '选择有效日期清错时同步停止原生动画，避免日历在选择后继续移动');
  editor.aboutToDisappear();
}

console.log('26) 控制器能力缺失时保持合法可选参数和失焦回退');
{
  fullUiSupported = false;
  const { editor, actions } = createEditor(initialData(), { section: 'future', testNodes: dateNodes() });
  editor.content = '不支持可选控制器';
  editor.focusedInput = 'task-content';
  editor.submit();
  assert(editor.contentController === undefined && editor.groupController === undefined &&
    editor.testClearFocusCalls === 1 && editor.dueDateError !== '' && actions.length === 0,
    '能力缺失时不创建或调用控制器，仍清焦点并显示日期校验提示');
  editor.aboutToDisappear();
  fullUiSupported = true;
}

console.log('27) 共用日历切换、清除与必填错误定位');
{
  const { editor, actions } = createEditor(initialData(), { section: 'future', testNodes: dateNodes() });
  assert(editor.dateField === 'due' && editor.calendarValue() === '' && editor.calendarMinimum() === '2026-10-16',
    '未来表单默认选择必填截止日期，沿用次日起的可选范围');
  editor.startDate = '2026-10-18'; editor.dueDate = '2026-10-20';
  editor.selectDateField('start');
  assert(editor.dateField === 'start' && editor.calendarValue() === '2026-10-18' &&
    editor.calendarMinimum() === '2026-10-16' && editor.dueDate === '2026-10-20',
    '切换起始选择项只更新日历焦点，不改已有区间');
  editor.selectCalendarDate('2026-10-21');
  assert(editor.startDate === '2026-10-21' && editor.dueDate === '2026-10-21',
    '共用日历选择起始日期继续执行原有区间联动规则');
  editor.clearStartDate();
  assert(editor.startDate === '' && editor.dueDate === '2026-10-21' && editor.calendarMinimum() === '2026-10-16',
    '清除可选起始日期保留截止日期并恢复默认范围');
  editor.selectDateField('due'); editor.selectCalendarDate('2026-10-22');
  assert(editor.dueDate === '2026-10-22' && editor.startDate === '' && editor.calendarValue() === '2026-10-22',
    '切换截止选择项后提交真实截止日期，起始仍可不填');
  editor.selectDateField('start'); editor.dueDate = ''; editor.content = '校验共用日历'; editor.submit();
  assert(editor.dateField === 'due' && editor.dueDateError && editor.dueDateScrollPending && actions.length === 0,
    '未填截止日期时自动切回截止日历并沿用提示和滚动定位，不提交数据');
  editor.aboutToDisappear();
}

console.log('28) 日期按钮始终读取当前日期，避免 Builder 捕获初始占位文案');
{
  const { editor, actions } = createEditor(initialData(), { section: 'future' });
  const renderStart = () => editor.dateLabelFromView('start');
  const renderDue = () => editor.dateLabelFromView('due');
  assert(renderStart() === '默认次日' && renderDue() === '请选择日期', '未选择日期时保留原有占位文案');
  editor.selectCalendarDate('2026-10-20');
  assert(renderDue() === '2026-10-20' && renderStart() === '默认次日' &&
    editor.dateAccessibilityFromView('due', '截止日期').endsWith('2026-10-20'), '选中截止后显示真实日期，无障碍文案同步');
  editor.selectDateField('start'); editor.selectCalendarDate('2026-10-18');
  assert(renderStart() === '2026-10-18' && renderDue() === '2026-10-20', '同一个按钮绑定可从占位更新为起始日期');
  editor.selectCalendarDate('2026-10-22');
  assert(renderStart() === '2026-10-22' && renderDue() === '2026-10-22', '起始晚于原截止时，区间联动后的两个按钮均刷新');
  editor.clearStartDate();
  assert(renderStart() === '默认次日' && renderDue() === '2026-10-22' &&
    editor.dateAccessibilityFromView('start', '起始日期').endsWith('默认次日'), '清除起始后仅该按钮恢复占位，不清空截止');
  editor.selectDateField('due'); editor.selectCalendarDate('2026-10-25');
  assert(renderDue() === '2026-10-25' && actions.length === 0, '反复改选只更新草稿和文案，不提前保存日程');
  editor.aboutToDisappear();
}
{
  const data = initialData();
  const task = new Task(); task.text = '已有未来安排'; task.startDate = '2026-10-18'; task.dueDate = '2026-10-21';
  const { editor } = createEditor(data, { section: 'future', mode: 'edit', task });
  assert(editor.dateLabelFromView('start') === task.startDate && editor.dateLabelFromView('due') === task.dueDate,
    '打开已有未来日程时直接显示原区间');
  editor.selectDateField('due'); editor.selectCalendarDate('2026-10-23');
  assert(editor.dateLabelFromView('due') === '2026-10-23' && editor.dateLabelFromView('start') === task.startDate,
    '编辑时改选截止不残留初始参数，也不改变起始');
  editor.aboutToDisappear();
}

console.log('29) 按压反馈在释放、取消和界面切换时清理');
{
  const { editor, actions } = createEditor();
  editor.buttonTouch('group-create', { type: TouchType.Down });
  assert(editor.buttonScale('group-create') === 0.97 && editor.buttonScale('task-submit') === 1,
    '按下只缩放当前按钮，保留明确且局部的触摸反馈');
  editor.buttonTouch('group-create', { type: TouchType.Move });
  assert(editor.pressedButton === 'group-create', '移动事件不会打断当前按压反馈');
  editor.buttonTouch('other', { type: TouchType.Up });
  assert(editor.pressedButton === 'group-create', '其他按钮释放不会清除新的按压状态');
  editor.buttonTouch('group-create', { type: TouchType.Cancel });
  assert(editor.pressedButton === '' && editor.buttonScale('group-create') === 1,
    '滑动接管或触摸取消时立即清理按压反馈');
  editor.buttonTouch('group-create', { type: TouchType.Down });
  editor.buttonTouch('group-create', { type: TouchType.Up });
  assert(editor.pressedButton === '', '正常触摸释放恢复按钮尺寸');
  editor.buttonTouch('group-create', { type: TouchType.Down });
  editor.createGroupFromView();
  assert(editor.creatingGroup && editor.pressedButton === '', '没有 Up 的真实创建按钮点击仍在展开表单前清理按压状态');
  editor.buttonTouch('group-cancel', { type: TouchType.Down });
  editor.cancelCreateFromView();
  assert(!editor.creatingGroup && editor.pressedButton === '', '真实局部取消按钮在收起内容前清理按压状态');
  editor.content = '按压后提交';
  let stateAtClose = 'unset';
  editor.onClose = () => { stateAtClose = editor.pressedButton; };
  editor.buttonTouch('task-submit', { type: TouchType.Down });
  editor.submitFromView();
  assert(stateAtClose === '' && actions.length === 1, '真实提交按钮先复位再保存与关闭，不依赖离场后的 Up');
  editor.buttonTouch('task-cancel', { type: TouchType.Down });
  editor.aboutToDisappear();
  assert(editor.pressedButton === '', '表单直接离场也清空未释放的触摸反馈');
}

console.log(`TaskEditor regression: ${passed} assertions passed.`);
