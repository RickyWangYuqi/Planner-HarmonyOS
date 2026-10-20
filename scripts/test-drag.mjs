// 从真实 Index.ets 提取拖动方法，配合真实 PlanerEngine 执行状态与落点契约回归。
// 只模拟 UIContext 的同步状态回调、FrameNode 几何和滚动器，不证明设备动画帧率或命中派发。
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
  try { ts = require(candidate); break; } catch { /* 使用已安装工具链，不下载依赖。 */ }
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向现有 TypeScript 模块。');
function transpile(source, filename) {
  const result = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, reportDiagnostics: true,
    fileName: filename
  });
  const errors = (result.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(ts.formatDiagnosticsWithColorAndContext(errors, {
    getCurrentDirectory: () => project, getCanonicalFileName: file => file, getNewLine: () => '\n'
  }));
  return result.outputText;
}
const modules = new Map();
function loadModel(name) {
  if (modules.has(name)) return modules.get(name);
  const filename = path.join(project, 'entry/src/main/ets/model', `${name}.ets`);
  const module = { exports: {} };
  const output = transpile(readFileSync(filename, 'utf8'), filename);
  vm.runInThisContext(`(function(require,module,exports){${output}\n})`, { filename })(
    request => loadModel(path.basename(request)), module, module.exports);
  modules.set(name, module.exports);
  return module.exports;
}
const { AppAction, Task } = loadModel('PlanerModel');
const { freshData, reduce } = loadModel('PlanerEngine');
const indexPath = path.join(project, 'entry/src/main/ets/pages/Index.ets');
const indexSource = readFileSync(indexPath, 'utf8');
const methodNames = ['tasks', 'currentIndex', 'currentTask', 'resetDrag', 'clearDrop', 'previewDrop', 'sourceCard',
  'samePosition', 'slotBeforeHeader', 'slotActive', 'slotId', 'pointerInSlot', 'hoverTask', 'finishDrop',
  'beginTaskDrag', 'beginGroupDrag', 'edgeScroll', 'openModal', 'closeModal', 'groupHead',
  'pointerAtSlot', 'previewTaskAt', 'hoverGroup', 'hoverList', 'leaveDrag', 'dragBounds', 'insideDragList',
  'validDragSection', 'edgeVelocity', 'stopEdgeScroll', 'queueEdgeFrame', 'stepEdgeScroll', 'refreshDragTarget',
  'tabsBottomPadding', 'futureExtension', 'splitBaseHeight', 'clampSplitRatio', 'todayPaneHeight', 'futureDragBottom', 'updateFutureTailSpace',
  'moreTasksBelow', 'recordVisibleItems', 'updateMoreBelow', 'moreHintVisible', 'startMoreObservation', 'stopMoreObservation', 'captureGroupMembers', 'groupLandingMembers', 'groupMemberSource', 'clearLandingLayout', 'refreshFinalDrop', 'clearFloating', 'floatingSource', 'floatingHeader', 'startFloating', 'updateFloating', 'moveFloating', 'floatingTouch', 'finishFloating'];
const methods = methodNames.map(name => {
  const match = indexSource.match(new RegExp('^  private ' + name + '\\([^]*?\\n  \\}', 'm'));
  if (!match) throw new Error(`Index.${name} 结构已变化，请更新测试提取边界。`);
  return match[0];
}).join('\n');
const frameClasses = ['DragScrollFrame', 'DragBounds', 'PlanerDragPoint'].map(name => {
  const match = indexSource.match(new RegExp('^class ' + name + '[^]*?\n\}', 'm'));
  if (!match) throw new Error('缺少真实帧类 ' + name);
  return match[0];
}).join('\n');
const memberPath = path.join(project, 'entry/src/main/ets/components/GroupDragVisual.ets');
const memberSource = readFileSync(memberPath, 'utf8').match(/^export class GroupDragMember[^]*?\n\}/m);
if (!memberSource) throw new Error('缺少真实 GroupDragMember 几何类。');
const memberClass = memberSource[0].replace('export ', '');
// 仅为组件框架提供内存状态；拖动判断和索引转换全部使用上方提取的原方法。
const modifierSource = readFileSync(path.join(project, 'entry/src/main/ets/theme/Appearance.ets'), 'utf8')
  .match(/^export class PlanerTabsModifier[^]*?\n\}/m)[0].replace('export ', '');
const shell = `
${frameClasses}
${memberClass}
${modifierSource}
class DragProbe {
  dragId = ''; dragSection = ''; dragIsGroup = false; dragGroup = null;
  dropSection = ''; dropIndex = -1; dropGroup = undefined; dragHeight = 58;
  modal = ''; sheetShown = false; selectedTask = new Task(); editorSection = 'today';
  selectedTarget = 0; selectedGroup = undefined; safeBottom = 0; paneHeight = 0; splitRatio = 0.45; futureTailSpace = 44; futureTop = 0; futureHeight = 300;
  ready = false; todayMoreBelow = false; futureMoreBelow = false; futureMoreInset = 0;
  todayFirstVisible = -1; todayLastVisible = -1; futureFirstVisible = -1; futureLastVisible = -1;
  moreLayout = undefined; rectMaps = { today: new Map(), future: new Map() }; rectReads = [];
  page = 0; dragPointerX = 0; dragPointerY = 0; dragHoverSection = '';
  edgeFramePending = false; edgeGeneration = 0; edgeFrameTime = 0; edgeLastOffset = 0;
  edgeExpectedMove = false; edgeStalledFrames = 0;
  floatingPhase = 'idle'; floatingTask = new Task(); floatingTasks = []; floatingMembers = []; floatingGroup = false;
  floatingSection = 'today'; floatingOrder = 1; floatingX = 0; floatingY = 0;
  floatingWidth = 1; floatingHeight = 1; floatingLift = 0; floatingGeneration = 0; floatingPointer = -1;
  floatingOriginX = 0; floatingOriginY = 0; floatingTouchX = 0; floatingTouchY = 0;
  floatingRootX = 0; floatingRootY = 0; floatingMoved = false;
  animationFinishes = []; immediateAnimations = 0; immediateSnapshots = []; landingLayout = undefined; layoutListeners = new Set();
  frameQueue = []; maxQueued = 0; clock = 1000000000;
  offsets = { today: 200, future: 200 }; limits = { today: 2000, future: 2000 };
  blocked = false; bound = true;
  frames = new Map(); actions = []; scrolls = []; scrollTos = []; animationCalls = 0;
  density = 2;
  todayScroller = this.scroller('today');
  futureScroller = this.scroller('future');
  constructor(data) {
    this.data = data;
    this.frame('list-today', 0, 2000);
    this.frame('list-future', 0, 2000);
    this.tabBar(2000);
    this.frame('planer-root', 0, 2000);
  }
  scroller(section) {
    return {
      getItemRect: index => {
        this.rectReads.push([section, index]);
        if (!this.bound) throw new Error('100004: controller not bound');
        return this.rectMaps[section].get(index) || { x: 0, y: 0, width: 0, height: 0 };
      },
      scrollBy: (x, y) => {
        this.scrolls.push([section, x, y]);
        if (!this.blocked) this.offsets[section] = Math.max(0, Math.min(this.limits[section], this.offsets[section] + y));
      },
      scrollTo: options => {
        this.scrollTos.push({ section, xOffset: options.xOffset, yOffset: options.yOffset,
          animation: options.animation, actionsAtCall: this.actions.length });
        if (!this.blocked) this.offsets[section] = Math.max(0, Math.min(this.limits[section], options.yOffset));
      },
      offset: () => this.bound ? { xOffset: 0, yOffset: this.offsets[section] } : undefined,
      isAtEnd: () => this.offsets[section] >= this.limits[section]
    };
  }
  itemRect(section, index, y, height, width = 320) {
    this.rectMaps[section].set(index, { x: 16, y, width, height });
  }
  runFrame(milliseconds = 16.666667) {
    this.clock += milliseconds * 1000000;
    const pending = this.frameQueue.splice(0);
    for (const frame of pending) frame.onFrame(this.clock);
  }
  runFrames(count, milliseconds = 16.666667) {
    for (let index = 0; index < count; index++) this.runFrame(milliseconds);
  }
  flushLayout() {
    for (const listener of Array.from(this.layoutListeners)) listener();
  }
  finishAnimations() {
    const pending = this.animationFinishes.splice(0);
    for (const finish of pending) finish();
  }
  memberSnapshot() {
    return { lift: this.floatingLift, members: this.floatingMembers.map(member => ({
      id: member.task.id, visible: member.visible, x: member.x, y: member.y, order: member.order
    })) };
  }
  getUIContext() {
    return {
      animateTo: (options, callback) => {
        this.animationCalls++; callback();
        if (options.onFinish) this.animationFinishes.push(options.onFinish);
      },
      animateToImmediately: (options, callback) => {
        const before = this.memberSnapshot();
        this.immediateAnimations++; callback();
        this.immediateSnapshots.push({ before, after: this.memberSnapshot() });
        if (options.onFinish) this.animationFinishes.push(options.onFinish);
      },
      getFrameNodeById: id => this.frames.get(id) || null,
      getUIObserver: () => ({
        on: (type, callback) => { if (type !== 'didLayout') throw new Error(type); this.layoutListeners.add(callback); },
        off: (type, callback) => { if (type !== 'didLayout') throw new Error(type); this.layoutListeners.delete(callback); }
      }),
      postFrameCallback: frame => { this.frameQueue.push(frame); this.maxQueued = Math.max(this.maxQueued, this.frameQueue.length); },
      px2vp: pixels => pixels / this.density
    };
  }
  dispatch(action) { this.actions.push(action); this.data = reduce(this.data, action); }
  frame(id, topVp, heightVp, section = '', leftVp = 0, widthVp = 400) {
    this.frames.set(id, { getPositionToWindow: () => ({ x: leftVp, y: topVp - (section ? this.offsets[section] : 0) }),
      getMeasuredSize: () => ({ width: widthVp * this.density, height: heightVp * this.density }),
      getNodeType: () => 'Row', getParent: () => null });
  }
  tabBar(top, height = 56) {
    const outer = { getNodeType: () => 'TabBar', getParent: () => null,
      getPositionToWindow: () => ({ x: 30, y: top }),
      getMeasuredSize: () => ({ width: 280 * this.density, height: height * this.density }) };
    const wrapper = { getNodeType: () => 'Row', getParent: () => outer };
    this.frames.set('tab-home', { getNodeType: () => 'Column', getParent: () => wrapper,
      getPositionToWindow: () => ({ x: 45, y: top + 8 }),
      getMeasuredSize: () => ({ width: 100 * this.density, height: 30 * this.density }) });
  }
  ${methods}
}
globalThis.DragProbe = DragProbe;
globalThis.ProbeTabsModifier = PlanerTabsModifier;
globalThis.ProbeGroupMember = GroupDragMember;
`;
const platform = { modern: true };
const context = vm.createContext({ AppAction, Task, reduce, FrameCallback: class {},
  deviceInfo: { apiAvailable: () => platform.modern }, Materials: { toolbar: () => undefined }, BlurStyle: { NONE: 0 },
  Motion: { quick: () => ({}), spring: () => ({}), drag: () => ({}) },
  DragResult: { DRAG_CANCELED: 'canceled', DRAG_SUCCESSFUL: 'success' },
  TouchType: { Down: 0, Up: 1, Move: 2, Cancel: 3 }
});
vm.runInContext(transpile(shell, indexPath), context, { filename: indexPath });
const DragProbe = context.DragProbe;
let passed = 0;
function assert(condition, message) {
  if (!condition) throw new Error(message);
  passed++;
  console.log(`✓ ${message}`);
}
function event(y = 100, x = 100) {
  return { result: null, getWindowX: () => x, getWindowY: () => y, setResult(value) { this.result = value; } };
}
function createProbe(today, future = [], grouped = false) {
  const data = freshData();
  data.currentDate = '2026-10-15';
  data.settings.showGroups = grouped;
  function task(spec) {
    const value = new Task();
    value.id = Array.isArray(spec) ? spec[0] : spec;
    value.text = value.id;
    value.group = Array.isArray(spec) ? spec[1] : null;
    value.createdAt = '2026-10-15T00:00:00.000Z';
    if (Array.isArray(spec)) { value.startDate = spec[2] || null; value.dueDate = spec[3] || null; }
    return value;
  }
  data.todayTasks = today.map(task);
  data.futureTasks = future.map(task);
  return new DragProbe(data);
}
function ids(tasks) { return tasks.map(task => task.id).join(','); }
function begin(probe, id, section = 'today') { probe.beginTaskDrag(probe.currentTask(section, id), section); }

console.log('1) 240 个同列表源移除前插入边界');
{
  const failures = [];
  let cases = 0;
  for (let count = 1; count <= 8; count++) {
    for (let source = 0; source < count; source++) {
      for (let boundary = 0; boundary <= count; boundary++) {
        const original = Array.from({ length: count }, (_, index) => `t${index}`);
        const probe = createProbe(original);
        begin(probe, original[source]);
        probe.previewDrop('today', boundary, null);
        const dragEvent = event();
        probe.finishDrop(dragEvent, 'today');
        const expected = original.slice();
        expected.splice(source, 1);
        expected.splice(boundary > source ? boundary - 1 : boundary, 0, original[source]);
        if (ids(probe.data.todayTasks) !== expected.join(',') || dragEvent.result !== 'success' || probe.dragId !== '') {
          failures.push({ count, source, boundary, actual: ids(probe.data.todayTasks), expected });
        }
        cases++;
      }
    }
  }
  assert(cases === 240 && failures.length === 0, `240 种边界转换、提交结果与拖动清理正确：${JSON.stringify(failures.slice(0, 2))}`);
}

console.log('2) 测量单位、源卡状态及原位空槽');
{
  const probe = createProbe(['a', 'b', 'c']);
  probe.frame('task-a', 100, 80);
  begin(probe, 'a');
  assert(probe.dragHeight === 80, '源卡 px 高度转换为 vp');
  assert(probe.sourceCard('today', 'a') && !probe.sourceCard('today', 'b') && !probe.sourceCard('future', 'a'), '仅正确分区的源卡进入拾起状态');
  probe.previewDrop('today', 0, null);
  assert(probe.samePosition() && !probe.slotActive('today', 'a', false), '原位前边界不重复展开占位');
  probe.previewDrop('today', 1, null);
  assert(probe.samePosition() && !probe.slotActive('today', 'b', false), '原位后边界不重复展开占位');
  probe.frame('task-b', 100, 400);
  begin(probe, 'b');
  assert(probe.dragHeight === 180, '过高预览槽按当前界面约束限制高度');
}

console.log('3) 单卡上下半区及中点迟滞');
{
  const probe = createProbe(['a', 'b', 'c']);
  begin(probe, 'a');
  probe.frame('task-b', 100, 60);
  probe.hoverTask(event(110), 'today', 'b');
  assert(probe.dropIndex === 1, '卡片上半区落在其前方');
  probe.hoverTask(event(150), 'today', 'b');
  assert(probe.dropIndex === 2, '卡片下半区落在其后方，几何高度正确换算');
  const animations = probe.animationCalls;
  probe.hoverTask(event(129), 'today', 'b');
  assert(probe.dropIndex === 2 && probe.animationCalls === animations, '中点四 vp 范围保留前次落点，不重复开启动画');
  probe.hoverTask(event(121), 'today', 'b');
  assert(probe.dropIndex === 1, '离开迟滞范围后允许切换前后边界');
}

console.log('4) 整组跨区清空与落地二次校验');
{
  const probe = createProbe([['a', 'A'], ['b', 'B']], [['f', 'F']], true);
  const before = JSON.stringify(probe.data);
  probe.beginGroupDrag('A', 'today');
  probe.previewDrop('today', 2, 'B');
  probe.previewDrop('future', 0, 'F');
  assert(probe.dropSection === '' && probe.dropIndex === -1 && probe.dropGroup === undefined, '整组进入其他分区清空旧落点');
  const dragEvent = event();
  probe.finishDrop(dragEvent, 'future');
  assert(dragEvent.result === 'canceled' && probe.actions.length === 0 && JSON.stringify(probe.data) === before, '非法跨区松手取消，不沿用原区旧位置提交');
}
{
  const probe = createProbe([['a', 'A'], ['b', 'B']], [['f', 'F']], true);
  probe.beginGroupDrag('A', 'today');
  probe.previewDrop('today', 2, 'B');
  const dragEvent = event();
  probe.finishDrop(dragEvent, 'future');
  assert(dragEvent.result === 'canceled' && probe.actions.length === 0, '即使没有触发跨区预览，实际松手分区仍校验');
}
{
  const probe = createProbe([['a', 'A'], ['b', 'B']], [['f', 'F']], true);
  probe.beginGroupDrag('A', 'today');
  probe.dropSection = 'future'; probe.dropIndex = 0; probe.dropGroup = 'F';
  const dragEvent = event();
  probe.finishDrop(dragEvent, 'future');
  assert(dragEvent.result === 'canceled' && probe.actions.length === 0, '残留或异常跨区组落点也被最终 guard 拒绝');
}

console.log('5) 整组前后边界与未分组');
{
  const probe = createProbe([['a', 'A'], ['b', 'A'], ['c', 'B'], ['d', 'B']], [], true);
  probe.beginGroupDrag('A', 'today');
  probe.frame('task-d', 100, 60);
  probe.hoverTask(event(110), 'today', 'd');
  assert(probe.dropIndex === 2, '整组悬停目标组内部上半卡时吸附到目标组首');
  probe.hoverTask(event(150), 'today', 'd');
  assert(probe.dropIndex === 4, '整组悬停下半卡时吸附到目标组末');
  assert(probe.slotActive('today', '', false) && !probe.slotActive('today', '', true), '整组队尾使用唯一末尾槽');
  probe.finishDrop(event(), 'today');
  assert(ids(probe.data.todayTasks) === 'c,d,a,b', '整组后移按移除前边界处理，保留内部顺序');
}
{
  const probe = createProbe([['a', 'A'], ['b', 'A'], ['c', null], ['d', null]], [], true);
  probe.beginGroupDrag(null, 'today');
  probe.frame('task-b', 100, 60);
  probe.hoverTask(event(110), 'today', 'b');
  probe.finishDrop(event(), 'today');
  assert(ids(probe.data.todayTasks) === 'c,d,a,b', '未分组也可作为完整组移动到前方');
}

console.log('6) 同一边界的不同分组归属与标题前后空槽');
{
  const probe = createProbe([['a', 'A'], ['b', 'A'], ['c', 'B']], [], true);
  begin(probe, 'a');
  probe.previewDrop('today', 2, 'A');
  assert(probe.slotBeforeHeader('today', 'c') && probe.slotActive('today', 'c', true) && !probe.slotActive('today', 'c', false), '归上一组时空槽显示在下一组标题之前');
  probe.frame(probe.slotId('today', 'c', true), 200, 70);
  assert(probe.pointerInSlot(event(250), 'today'), '防抖命中使用同一个标题前槽 ID');
  probe.previewDrop('today', 2, 'B');
  assert(probe.dropGroup === 'B' && !probe.slotBeforeHeader('today', 'c'), '同索引切换目标组会刷新归属');
  assert(probe.slotActive('today', 'c', false) && !probe.slotActive('today', 'c', true), '归下一组时空槽显示在其标题之后');
  probe.frame(probe.slotId('today', 'c', false), 300, 70);
  assert(probe.pointerInSlot(event(350), 'today') && !probe.pointerInSlot(event(250), 'today'), '归属切换后防抖采用新的标题后槽');
  probe.finishDrop(event(), 'today');
  assert(ids(probe.data.todayTasks) === 'b,a,c' && probe.data.todayTasks[1].group === 'B', '落地顺序与实际分组和预览一致');
}

console.log('7) 活动槽防抖、取消与无效源');
{
  const probe = createProbe(['a', 'b', 'c']);
  begin(probe, 'a');
  probe.previewDrop('today', 2, null);
  probe.frame(probe.slotId('today', 'c', false), 200, 72);
  probe.frame('task-b', 100, 60);
  assert(probe.pointerInSlot(event(273), 'today') && !probe.pointerInSlot(event(276), 'today'), '槽高度按 px 转 vp，边缘三 vp 容差正确');
  const animations = probe.animationCalls;
  probe.hoverTask(event(210), 'today', 'b');
  assert(probe.dropIndex === 2 && probe.animationCalls === animations, '指针处于已展开槽时锁定落点，不随相邻卡片位移改判');
  assert(!probe.pointerInSlot(event(210), 'future'), '其他分区不能命中当前活动槽');
  const before = JSON.stringify(probe.data);
  probe.resetDrag();
  assert(JSON.stringify(probe.data) === before && probe.actions.length === 0 && probe.dragId === '' && probe.dropIndex === -1, '取消拖动仅清理交互状态，不修改业务数据');
}
{
  const probe = createProbe(['a', 'b']);
  begin(probe, 'a');
  probe.previewDrop('today', 2, null);
  probe.data.todayTasks = probe.data.todayTasks.filter(task => task.id !== 'a');
  const before = JSON.stringify(probe.data);
  const dragEvent = event();
  probe.finishDrop(dragEvent, 'today');
  assert(dragEvent.result === 'canceled' && probe.actions.length === 0 && JSON.stringify(probe.data) === before, '源任务已不存在时取消而不移动其他日程');
}

console.log('8) 跨列表日期契约');
{
  const probe = createProbe([['a', 'A']], [['f', 'F']], true);
  const before = JSON.stringify(probe.data);
  begin(probe, 'a');
  probe.previewDrop('future', 0, 'F');
  const dragEvent = event();
  probe.finishDrop(dragEvent, 'future');
  assert(probe.modal === 'move' && probe.sheetShown && probe.selectedTask.id === 'a', '当日拖到未来先打开日期表单');
  assert(probe.selectedTarget === 0 && probe.selectedGroup === 'F' && probe.editorSection === 'future', '日期表单保留目标索引与分组');
  assert(probe.actions.length === 0 && JSON.stringify(probe.data) === before && dragEvent.result === 'success', '打开未来日期表单时尚不提交移动数据');
  probe.closeModal();
  assert(!probe.sheetShown && JSON.stringify(probe.data) === before, '取消日期表单保留原任务及两区数据');
}
{
  const probe = createProbe([['a', 'A']], [['f', 'F', '2026-10-16', '2026-10-18']], true);
  begin(probe, 'f', 'future');
  probe.previewDrop('today', 0, 'A');
  probe.finishDrop(event(), 'today');
  assert(ids(probe.data.todayTasks) === 'f,a' && probe.data.futureTasks.length === 0, '未来拖到当日按目标边界移动');
  assert(probe.data.todayTasks[0].group === 'A' && probe.data.todayTasks[0].startDate === '2026-10-16' && probe.data.todayTasks[0].dueDate === '2026-10-18', '跨到当日更新组归属并保留隐藏起止日期');
}
{
  const probe = createProbe([['a', 'A'], ['b', 'B']], [], false);
  begin(probe, 'a');
  probe.previewDrop('today', 2, 'B');
  probe.finishDrop(event(), 'today');
  assert(ids(probe.data.todayTasks) === 'b,a' && probe.data.todayTasks[1].group === 'A', '关闭分组时拖动不修改隐藏归属');
}

console.log('9) 帧驱动连续滚动、速度对称和生命周期清理');
function scrollProbe(grouped = false) {
  const specs = Array.from({ length: 24 }, (_, index) => grouped ? ['t' + index, 'G' + Math.floor(index / 4)] : 't' + index);
  const probe = createProbe(specs, [['f', 'F']], grouped);
  probe.frame('list-today', 0, 300);
  probe.frame('list-future', 400, 300);
  probe.tabBar(700);
  probe.offsets.today = 200;
  probe.offsets.future = 0;
  probe.limits.today = 1140;
  probe.limits.future = 1000;
  for (let index = 0; index < 24; index++) probe.frame('task-t' + index, index * 60, 52, 'today');
  probe.frame('list-end-today', 1440, 40, 'today');
  return probe;
}
{
  const probe = scrollProbe();
  begin(probe, 't0');
  probe.dragPointerX = 100;
  probe.dragPointerY = 10;
  const topSpeed = probe.edgeVelocity('today');
  probe.dragPointerY = 290;
  const bottomSpeed = probe.edgeVelocity('today');
  assert(topSpeed < 0 && bottomSpeed > 0 && Math.abs(topSpeed + bottomSpeed) < 0.0001, '上下相同边缘距离得到等幅反向平滑速度');
  probe.dragPointerY = 45;
  assert(Math.abs(probe.edgeVelocity('today')) < Math.abs(topSpeed), '接近边缘逐渐加速，进入区域时没有固定步长跳变');
  probe.dragPointerY = 150;
  assert(probe.edgeVelocity('today') === 0, '列表中心不自动滚动');
  probe.frame('list-today', 0, 60);
  probe.dragPointerY = 30;
  assert(probe.edgeVelocity('today') === 0, '小高度列表上下触发区不重叠');
  probe.dragPointerY = 5; probe.dragPointerX = -1;
  assert(probe.edgeVelocity('today') === 0, '横向移出列表不继续滚动');
}
{
  const probe = scrollProbe();
  begin(probe, 't0');
  probe.hoverList(event(290), 'today');
  const firstTarget = probe.dropIndex;
  const before = JSON.stringify(probe.data);
  for (let index = 0; index < 50; index++) probe.edgeScroll(event(290), 'today');
  assert(probe.frameQueue.length === 1 && probe.maxQueued === 1, '高频父子移动事件只安排一个待处理系统帧');
  probe.runFrames(18);
  assert(probe.offsets.today > 280 && probe.scrolls.length === 18, '只需一次指针位置，手指静止仍逐帧连续下滚');
  assert(probe.dropIndex > firstTarget, '滚动后按当前卡片几何更新落点，不沿用旧 hoverTask ID');
  assert(JSON.stringify(probe.data) === before && probe.actions.length === 0, '自动滚动与悬停仅改变落点，尚未提交业务数据');
  assert(probe.maxQueued === 1, '连续多帧也不累积回调队列');
  probe.edgeScroll(event(150), 'today');
  const count = probe.scrolls.length;
  probe.runFrames(3);
  assert(probe.scrolls.length === count && probe.frameQueue.length === 0, '返回中心后停止，旧回调不会额外滚动');
}
{
  const probe = scrollProbe();
  begin(probe, 't23');
  probe.hoverList(event(10), 'today');
  const target = probe.dropIndex;
  probe.runFrames(12);
  assert(probe.offsets.today < 130 && probe.dropIndex < target, '指针静止时向上持续滚动并更新更早落点');
  const before = probe.offsets.today;
  probe.runFrame(3000);
  assert(before - probe.offsets.today <= 420 * 0.032 + 0.001, '卡顿或后台时间差被限制，不产生超大滚动跳跃');
}
{
  const probe = scrollProbe(true);
  probe.beginGroupDrag('G0', 'today');
  probe.previewDrop('today', 8, 'G2');
  probe.frame(probe.slotId('today', 't8', true), 205, 188);
  probe.hoverList(event(290), 'today');
  assert(probe.dropIndex === 8, '未滚动时保留大分组槽内防抖');
  probe.runFrames(5);
  assert(probe.dropIndex > 8, '已有实际滚动后跳出旧大槽锁定，按新几何更新整组边界');
}
{
  const probe = scrollProbe(true);
  probe.beginGroupDrag('G0', 'today');
  probe.frame('group-today-t8', 270, 44);
  probe.hoverGroup(event(290), 'today', 't8');
  probe.leaveDrag(event(285), 'today');
  assert(probe.dragHoverSection === 'today' && probe.frameQueue.length === 1, '标题跟踪指针，离开子卡但仍在列表内不误停循环');
  probe.runFrames(2);
  assert(probe.offsets.today > 200, '组标题区域也能持续自动滚动');
  probe.leaveDrag(event(290, 500), 'today');
  const count = probe.scrolls.length;
  probe.runFrames(2);
  assert(probe.dragHoverSection === '' && probe.scrolls.length === count && probe.dropIndex === -1, '真正移出列表清理落点并停止旧帧');
}
{
  const probe = scrollProbe(true);
  probe.beginGroupDrag('G0', 'today');
  probe.hoverList(event(290), 'today');
  probe.hoverList(event(690), 'future');
  probe.runFrames(3);
  assert(probe.scrolls.length === 0 && probe.dropIndex === -1 && probe.frameQueue.length === 0, '整组跨区在滚动之前拒绝，不滚错误列表也不保留旧循环');
}
{
  const probe = scrollProbe();
  begin(probe, 't0');
  probe.hoverList(event(290), 'today');
  probe.runFrame();
  const todayOffset = probe.offsets.today;
  probe.hoverList(event(690), 'future');
  probe.runFrames(3);
  assert(probe.offsets.today === todayOffset && probe.offsets.future > 0 && probe.maxQueued === 1, '换区后旧帧失效，只滚新列表且不重复排帧');
  const futureScrolls = probe.scrolls.filter(scroll => scroll[0] === 'future');
  assert(futureScrolls[0][2] < 8, '新分区首帧重置时间基准，不继承旧区累积时间');
}
{
  const probe = scrollProbe();
  begin(probe, 't0');
  probe.offsets.today = 0;
  probe.hoverList(event(5), 'today');
  probe.runFrames(3);
  assert(probe.scrolls.length === 0 && probe.frameQueue.length === 0, '达到列表顶部不继续施加越界滚动');
  probe.offsets.today = probe.limits.today;
  probe.hoverList(event(295), 'today');
  probe.runFrames(3);
  assert(probe.scrolls.length === 0 && probe.frameQueue.length === 0, '达到列表底部停止，不让 Spring 边界反复抖动');
}
{
  const probe = scrollProbe();
  begin(probe, 't0');
  probe.blocked = true;
  probe.hoverList(event(290), 'today');
  probe.runFrames(8);
  assert(probe.scrolls.length === 3 && probe.frameQueue.length === 0, '偏移连续三帧不推进时停止，不产生无限空循环');
  probe.bound = false;
  probe.hoverList(event(290), 'today');
  probe.runFrames(2);
  assert(probe.scrolls.length === 3 && probe.frameQueue.length === 0, '滚动器未绑定时安全停止');
}
{
  const probe = scrollProbe();
  begin(probe, 't0');
  probe.hoverList(event(290), 'today');
  const before = JSON.stringify(probe.data);
  probe.resetDrag();
  probe.runFrames(4);
  assert(probe.scrolls.length === 0 && probe.frameQueue.length === 0 && JSON.stringify(probe.data) === before, '取消或页面隐藏清理后，旧帧不滚动、不写业务数据');
  begin(probe, 't0');
  probe.hoverList(event(290), 'today');
  probe.openModal('move');
  probe.runFrames(3);
  assert(probe.scrolls.length === 0 && probe.frameQueue.length === 0, '打开日期弹层立即终止边缘滚动');
}
{
  const probe = scrollProbe();
  begin(probe, 't0');
  probe.hoverList(event(290), 'today');
  const drop = event(290);
  probe.finishDrop(drop, 'today');
  probe.finishDrop(drop, 'today');
  probe.runFrames(3);
  assert(probe.actions.length === 1 && drop.result === 'success' && probe.scrolls.length === 0, '子卡与父 List 重复 Drop 不重复提交、不把成功覆盖为取消');
}


console.log('10) 未布局末尾几何与滚动后立即落地');
{
  const probe = scrollProbe();
  begin(probe, 't0');
  probe.frame('list-end-today', 0, 0);
  probe.hoverList(event(150), 'today');
  assert(probe.dropIndex === 6, '未布局末尾 height=0/top=0 不抢占指针下方卡片');
  probe.frame('list-end-today', -80, 40);
  probe.hoverList(event(150), 'today');
  assert(probe.dropIndex === 6, '离屏旧末尾矩形不把向上回滚误判为队尾');
  probe.frame('list-end-today', 100, 20);
  probe.hoverList(event(150), 'today');
  assert(probe.dropIndex === 6, '指针已越过末尾实际矩形时不沿用其顶部判断');
  probe.frame('list-end-today', 130, 40);
  probe.hoverList(event(150), 'today');
  assert(probe.dropIndex === 24, '有效可视末尾命中仍可移到完整列表队尾');
}
{
  const probe = scrollProbe();
  begin(probe, 't0');
  probe.frame('task-t8', 480, 40, 'today');
  probe.hoverList(event(295), 'today');
  assert(probe.dropIndex === 8, '即时落地用例初始指针在目标卡上半部');
  probe.runFrame();
  const drop = event(295);
  probe.finishDrop(drop, 'today');
  probe.runFrames(3);
  assert(drop.result === 'success' && probe.actions.length === 1 && probe.data.todayTasks.findIndex(task => task.id === 't0') === 8,
    '最后 scrollBy 后立即 Drop 使用当前几何，不提交上一帧过期边界');
}


console.log('11) 未来区延展、安全避让与分隔位置兼容');
{
  const probe = createProbe(['a'], ['f']);
  probe.safeBottom = 34;
  probe.paneHeight = 630;
  assert(probe.tabsBottomPadding() === 0 && probe.futureExtension() === 130, 'API 26 内容铺到屏幕底，延展包含原96与手势区34');
  assert(probe.splitBaseHeight() === 500 && probe.todayPaneHeight() === 225, '正常尺寸保留原比例分母与当日225vp高度，分隔条不下移');
  assert(probe.paneHeight - probe.todayPaneHeight() === 275 + 130, '新增高度全部归未来区，不挤大当日区域');
  probe.splitRatio = 1;
  assert(probe.todayPaneHeight() === 380, '分隔条极值仍为原未来操作区保留120vp，延展另行补足');
  probe.paneHeight = 0;
  assert(probe.todayPaneHeight() === '40%', '首次测量前提供比例占位，不产生负高度');
  probe.paneHeight = 100;
  assert(probe.splitBaseHeight() === 50 && probe.todayPaneHeight() > 0 && probe.todayPaneHeight() < 100, '极小窗口限制延展预算，两区计算不出现负值或撑出容器');
  platform.modern = false;
  probe.paneHeight = 596; probe.splitRatio = 0.45;
  assert(probe.tabsBottomPadding() === 34 && probe.futureExtension() === 96 && probe.todayPaneHeight() === 225, '旧系统保留外层安全区与同一原分隔位置');
  platform.modern = true;
}
{
  const probe = createProbe(['a'], ['f']);
  probe.safeBottom = 34;
  probe.frame('list-today', 0, 300);
  probe.frame('list-future', 400, 400);
  probe.tabBar(700);
  assert(probe.dragBounds('future').height === 300, '未来列表绘制400vp，但拖动区域止于实测TabBar外框顶边');
  assert(probe.dragBounds('today').height === 300, '当日区域拖动几何不受底栏避让影响');
  assert(probe.insideDragList('future', 100, 690) && !probe.insideDragList('future', 100, 710), '浮栏上方仍可触发，下方遮挡区不接受拖动落点');
  probe.dragPointerX = 100; probe.dragPointerY = 690;
  assert(probe.edgeVelocity('future') > 0, '向下连续滚动热区位于导航栏上方，可真实触达');
  probe.frames.delete('tab-home');
  assert(probe.dragBounds('future').height === 270, '找不到原生TabBar时采用96+safeBottom的保守回退');
  probe.tabBar(700, 0);
  assert(probe.dragBounds('future').height === 270, '未完成测量的TabBar不把热区绑定到无效矩形');
  probe.tabBar(700);
  probe.frame('list-future', 740, 60);
  assert(probe.dragBounds('future') === null, '列表完全落于遮挡区时不虚构可交互高度');
}
{
  const modifier = new context.ProbeTabsModifier({}, 34);
  let floating;
  modifier.applyNormalAttribute({ barFloatingStyle: value => { floating = value; } });
  assert(floating.barBottomMargin === 46, '原生浮栏将安全区加入自身间距，视觉位置保持原12+34');
  platform.modern = false;
  const calls = [];
  const instance = {
    barBackgroundColor: () => { calls.push('color'); return instance; },
    barHeight: value => { calls.push(value); return instance; },
    barBackgroundBlurStyle: () => instance
  };
  modifier.applyNormalAttribute(instance);
  assert(calls.join(',') === 'color,64', '旧系统仍使用原64vp普通底栏，不调用新API');
  platform.modern = true;
}


console.log('12) 末尾留白扣除已有尾部空间');
{
  const probe = createProbe(['a'], ['f']);
  probe.safeBottom = 34;
  probe.futureTop = 400; probe.futureHeight = 220;
  probe.tabBar(524);
  probe.updateFutureTailSpace();
  assert(probe.futureTailSpace === 44, '实测遮挡96vp扣已有60vp并留8vp安全间距，补44vp即可');
  assert(probe.futureExtension() === 130, '尾部精简不改变未来延展量和原分隔条基准');
  const cardBottom = 220 - 12 - 40 - 8 - probe.futureTailSpace;
  assert(cardBottom - 80 >= 12 && cardBottom === 124 - 8, '220vp视口内80vp末卡在终点完整可见，底部仍距导航栏8vp');
  let writes = 0;
  let value = probe.futureTailSpace;
  Object.defineProperty(probe, 'futureTailSpace', { get: () => value, set: next => { value = next; writes++; } });
  probe.updateFutureTailSpace();
  probe.futureHeight = 220.2;
  probe.updateFutureTailSpace();
  assert(writes === 0, '同尺寸或亚像素抖动不反复更新响应式状态');
  probe.futureHeight = 221;
  probe.updateFutureTailSpace();
  assert(writes === 1 && value === 45, '真实尺寸变化更新一次尾部留白');
  probe.frames.delete('tab-home');
  probe.updateFutureTailSpace();
  assert(probe.futureTailSpace === 78, '首次未取得TabBar测量时仍用保守遮挡回退并扣除已有空间');
  probe.tabBar(probe.futureTop + probe.futureHeight);
  probe.updateFutureTailSpace();
  assert(probe.futureTailSpace === 0, '没有导航遮挡时不增加负值或多余尾部空间');
}

console.log('13) 识别同步拾起、同一浮层与窗口坐标');
function gesture(x = 100, y = 110, id = 0) {
  return { fingerList: [{ id, globalX: x, globalY: y }], fingerInfos: [{ id, globalX: x, globalY: y }] };
}
function touch(type, x = 100, y = 110, id = 0) {
  return { type, changedTouches: [{ id, windowX: x, windowY: y }] };
}
function floatingProbe(today = ['a', 'b', 'c'], future = ['f'], grouped = false) {
  const probe = createProbe(today, future, grouped);
  probe.frame('planer-root', 30, 800, '', 17, 400);
  probe.frame('list-today', 60, 300);
  probe.frame('list-future', 420, 260);
  probe.tabBar(680);
  probe.data.todayTasks.forEach((task, index) => probe.frame('task-' + task.id, 80 + index * 80, 50, '', 45, 320));
  probe.data.futureTasks.forEach((task, index) => probe.frame('task-' + task.id, 450 + index * 80, 50, '', 45, 320));
  return probe;
}
{
  const probe = floatingProbe();
  probe.frame('task-a', 120, 80, '', 45, 320);
  probe.startFloating(gesture(80, 150), 'today', 'a');
  assert(probe.floatingPhase === 'lifting' && probe.floatingLift === 1 && probe.immediateAnimations === 1,
    '长按识别调用返回前已提交唯一浮层的浮起动画，不等待800ms原生阶段');
  assert(probe.frameQueue.length === 0 && probe.layoutListeners.size === 0 && probe.animationFinishes.length === 0,
    '拾起不依赖定时器、额外系统帧或另一段动画结束');
  assert(probe.floatingX === 28 && probe.floatingY === 90 && probe.floatingWidth === 320 && probe.floatingHeight === 80,
    '浮层初始位置减去根窗口偏移，测量px尺寸转换为vp');
  assert(probe.floatingSource('a') && !probe.floatingSource('b') && probe.floatingTask !== probe.data.todayTasks[0],
    '仅源卡进入浮层状态，显示内容使用独立任务快照');
  probe.updateFloating(gesture(400, 400, 9));
  assert(probe.floatingX === 28 && probe.floatingY === 90 && !probe.floatingMoved, '其他手指不带动当前浮层');
  probe.updateFloating(gesture(120, 210));
  assert(probe.floatingX === 68 && probe.floatingY === 150 && probe.floatingPhase === 'dragging',
    '同一浮层直接按窗口vp差值跟手，不重复应用像素缩放');
  probe.frame('task-a', 10, 80, '', 5, 320);
  probe.updateFloating(gesture(130, 220));
  assert(probe.floatingX === 78 && probe.floatingY === 160, '源卡因占位或滚动改变布局时，跟手位置仍由原始触点连续计算');
}
{
  const probe = floatingProbe();
  probe.startFloating({ fingerList: [] }, 'today', 'a');
  assert(probe.floatingPhase === 'idle' && probe.dragId === '', '无有效手指的识别事件不创建残留拖动');
  probe.frame('task-a', 80, 0);
  probe.startFloating(gesture(), 'today', 'a');
  assert(probe.floatingPhase === 'idle' && probe.frameQueue.length === 0, '源卡未布局时不创建尺寸为零的浮层');
}

console.log('14) 原地松手、取消和重复终止');
{
  const probe = floatingProbe();
  const before = JSON.stringify(probe.data);
  probe.startFloating(gesture(), 'today', 'a');
  probe.floatingTouch(touch(context.TouchType.Up, 100, 110, 3));
  assert(probe.floatingPhase === 'lifting', '非活动手指抬起不会终止拖动');
  probe.floatingTouch(touch(context.TouchType.Up));
  assert(probe.floatingPhase === 'settling' && probe.actions.length === 0 && probe.layoutListeners.size === 1 && probe.frameQueue.length === 0,
    '长按后不移动直接松手也回落，只监听一次布局完成');
  probe.finishFloating(true);
  probe.finishFloating(false);
  assert(probe.layoutListeners.size === 1 && probe.frameQueue.length === 0 && JSON.stringify(probe.data) === before,
    'Up、PanEnd和Cancel重复到达不重复监听布局、不重复提交');
  probe.flushLayout();
  assert(probe.floatingPhase === 'settling' && probe.floatingSource('a') && probe.floatingLift === 0 && probe.animationFinishes.length === 1,
    '落位动画执行时保留原浮层，结束前不提前显示另一张卡');
  probe.finishAnimations();
  assert(probe.floatingPhase === 'idle' && probe.floatingPointer === -1 && !probe.floatingSource('a') && JSON.stringify(probe.data) === before,
    '唯一落位动画完成后恢复源卡，原地释放全过程不改数据');
}
{
  const probe = floatingProbe();
  const before = JSON.stringify(probe.data);
  probe.startFloating(gesture(), 'today', 'a');
  probe.moveFloating(100, 275);
  probe.floatingTouch({ type: context.TouchType.Cancel, changedTouches: [] });
  probe.flushLayout(); probe.finishAnimations();
  assert(probe.actions.length === 0 && JSON.stringify(probe.data) === before && probe.floatingPhase === 'idle',
    '系统触摸取消即使没有changedTouches也安全回源，不提交已预览的落点');
}

console.log('15) 提交后测量目标、代次隔离与同一对象落位');
{
  const probe = floatingProbe();
  probe.startFloating(gesture(), 'today', 'a');
  const captured = probe.floatingTask;
  probe.moveFloating(100, 275);
  probe.floatingTouch(touch(context.TouchType.Up, 100, 275));
  probe.finishFloating(true);
  assert(ids(probe.data.todayTasks) === 'b,c,a' && probe.actions.length === 1 && probe.floatingPhase === 'settling',
    '松手先提交一次真实排序，重复PanEnd不再次移动');
  const beforeLayoutY = probe.floatingY;
  probe.runFrame();
  assert(probe.floatingY === beforeLayoutY && probe.animationFinishes.length === 0 && probe.layoutListeners.size === 1,
    '帧开始未完成布局时不测旧目标，也不启动落位动画');
  probe.frame('task-a', 265, 50, '', 49, 320);
  probe.flushLayout();
  assert(probe.floatingX === 32 && probe.floatingY === 235 && probe.floatingTask.id === captured.id && probe.floatingOrder === 3,
    '布局完成后测量真实目标位置，同一浮层更新序号并连续落到新位置');
  probe.startFloating(gesture(), 'today', 'b');
  assert(probe.floatingTask.id === captured.id && probe.immediateAnimations === 2, '落位尚未结束时拒绝第二次拾起');
  probe.finishAnimations();
  assert(probe.floatingPhase === 'idle' && probe.dragId === '' && probe.dropIndex === -1,
    '落位结束清理浮层和业务拖动状态');
}
{
  const probe = floatingProbe();
  probe.startFloating(gesture(), 'today', 'a');
  probe.finishFloating(false);
  probe.flushLayout();
  const oldFinish = probe.animationFinishes.shift();
  probe.resetDrag();
  probe.startFloating(gesture(100, 190), 'today', 'b');
  oldFinish();
  assert(probe.floatingPhase === 'lifting' && probe.floatingTask.id === 'b' && probe.floatingLift === 1,
    '旧落位动画onFinish不能清理新一轮浮层');
  probe.finishFloating(false);
  const oldLayout = probe.landingLayout;
  probe.resetDrag();
  probe.startFloating(gesture(100, 270), 'today', 'c');
  oldLayout();
  probe.flushLayout();
  assert(probe.floatingPhase === 'lifting' && probe.floatingTask.id === 'c' && probe.animationFinishes.length === 0 && probe.layoutListeners.size === 0,
    '旧布局监听已注销，滞后回调不能给新拖动补上过时动画');
}

console.log('16) 浮层跨区日期确认及整组限制');
{
  const probe = floatingProbe([['a', 'A']], [['f', 'F']], true);
  const before = JSON.stringify(probe.data);
  probe.startFloating(gesture(), 'today', 'a');
  probe.moveFloating(100, 480);
  probe.finishFloating(true);
  assert(probe.floatingPhase === 'settling' && !probe.sheetShown && probe.actions.length === 0,
    '当日拖到未来先开始回落，不立即打开日期弹层或提交移动');
  probe.flushLayout();
  assert(!probe.sheetShown && probe.floatingX === 28 && probe.floatingY === 50,
    '日期未确认时同一浮层回源，动画中途不弹出表单');
  probe.finishAnimations();
  assert(probe.floatingPhase === 'idle' && probe.sheetShown && probe.modal === 'move' && probe.selectedTask.id === 'a',
    '回落完成后才打开真实日期表单');
  assert(probe.selectedGroup === 'F' && probe.selectedTarget === 1 && probe.editorSection === 'future' && JSON.stringify(probe.data) === before,
    '延后打开仍保留目标分组与插入索引，业务数据未提前改变');
  probe.closeModal();
  assert(!probe.sheetShown && JSON.stringify(probe.data) === before, '取消日期表单不改变跨区前数据');
}
{
  const probe = floatingProbe([['a', 'A']], [['f', 'F', '2026-10-16', '2026-10-18']], true);
  probe.startFloating(gesture(100, 470), 'future', 'f');
  probe.moveFloating(100, 90);
  probe.finishFloating(true);
  probe.frame('task-f', 80, 62, '', 45, 310);
  probe.flushLayout(); probe.finishAnimations();
  assert(probe.floatingSection === 'today' && probe.floatingOrder === 1 && probe.floatingWidth === 310 && probe.floatingHeight === 62,
    '跨区落位同步目标样式、序号与实测尺寸，结束时不再切换第二种卡片');
  assert(ids(probe.data.todayTasks) === 'f,a' && probe.data.futureTasks.length === 0 && !probe.sheetShown,
    '未来拖到当日完成直接提交和落位，不错误打开日期表单');
  assert(probe.data.todayTasks[0].group === 'A' && probe.data.todayTasks[0].startDate === '2026-10-16' && probe.data.todayTasks[0].dueDate === '2026-10-18',
    '浮层路径仍遵守跨区更新分组但保留隐藏日期的业务契约');
}
{
  const probe = floatingProbe([['a', 'A'], ['b', 'A'], ['c', 'B']], [['f', 'F']], true);
  probe.frame('group-today-a', 60, 44, '', 45, 320);
  probe.startFloating(gesture(100, 80), 'today', 'a', true);
  assert(probe.floatingGroup && probe.floatingSource('a') && probe.floatingSource('b') && !probe.floatingSource('c') &&
    probe.floatingHeader('today', 'a') && !probe.floatingHeader('future', 'a'),
    '整组统一浮层仅标记本组卡片与源组标题');
  assert(probe.floatingWidth === 272 && probe.floatingX === 52, '分组摘要浮层按源标题宽度居中，坐标仍扣根偏移');
  const before = JSON.stringify(probe.data);
  probe.moveFloating(100, 480);
  probe.finishFloating(true);
  probe.runFrames(2); probe.flushLayout(); probe.finishAnimations();
  assert(probe.actions.length === 0 && JSON.stringify(probe.data) === before && !probe.sheetShown && probe.floatingPhase === 'idle',
    '整组跨区无效时返回源位置，不打开单卡日期表单');
}
{
  const probe = floatingProbe();
  const before = JSON.stringify(probe.data);
  probe.startFloating(gesture(), 'today', 'a');
  probe.moveFloating(100, 275);
  probe.moveFloating(500, 275);
  probe.finishFloating(true);
  probe.runFrames(2); probe.flushLayout(); probe.finishAnimations();
  assert(probe.actions.length === 0 && JSON.stringify(probe.data) === before && probe.dropIndex === -1,
    '浮层移出所有有效列表后松手，不沿用最后一次有效落点');
}

console.log('17) 实际浮层松手保留最后一帧滚动后的落点');
{
  const probe = scrollProbe();
  probe.frame('planer-root', 0, 800);
  probe.frame('task-t8', 480, 40, 'today');
  probe.startFloating(gesture(100, 90), 'today', 't4');
  probe.moveFloating(100, 295);
  assert(probe.dropIndex === 8, '浮层边缘松手用例初始命中目标卡上半区');
  probe.runFrame();
  probe.finishFloating(true);
  assert(probe.actions.length === 1 && probe.data.todayTasks.findIndex(task => task.id === 't4') === 8,
    'finishFloating不提前清除滚动偏移证据，提交使用最后scrollBy后的下半区边界');
  probe.runFrames(3); probe.flushLayout(); probe.finishAnimations();
  assert(probe.floatingPhase === 'idle' && probe.frameQueue.length === 0, '连续滚动与落位均完成后不残留活动帧');
}
console.log('18) 有效触点与延迟日期回调边界');
{
  const probe = floatingProbe();
  const fingers = new Array(3);
  fingers[2] = { id: 2, globalX: 100, globalY: 110 };
  probe.startFloating({ fingerList: fingers, fingerInfos: [fingers[2]] }, 'today', 'a');
  assert(probe.floatingPhase === 'lifting' && probe.floatingPointer === 2,
    'fingerList含空位时从fingerInfos有效点启动，不访问空项');
  const moved = { id: 2, globalX: 110, globalY: 130 };
  probe.updateFloating({ fingerList: new Array(3), fingerInfos: [moved] });
  assert(probe.floatingPhase === 'dragging' && probe.floatingX === 38 && probe.floatingY === 70,
    '多点手势更新也按有效指针而非稀疏数组索引跟手');
}
{
  const probe = floatingProbe();
  probe.startFloating(gesture(), 'today', 'a');
  probe.moveFloating(100, 480);
  probe.finishFloating(true);
  probe.flushLayout();
  const delayedFinish = probe.animationFinishes.shift();
  probe.resetDrag();
  delayedFinish();
  assert(!probe.sheetShown && probe.actions.length === 0 && probe.floatingPhase === 'idle',
    '日期回落期间页面隐藏或取消后，旧onFinish不能再次弹出日期表单');
}
{
  const probe = scrollProbe();
  probe.frame('planer-root', 0, 800);
  probe.frame('task-f', 680, 40, 'future');
  probe.startFloating(gesture(100, 90), 'today', 't4');
  probe.moveFloating(100, 695);
  assert(probe.dropSection === 'future' && probe.dropIndex === 0, '未来边缘滚动前，指针位于末卡上半区');
  probe.runFrame();
  probe.finishFloating(true);
  probe.flushLayout(); probe.finishAnimations();
  assert(probe.sheetShown && probe.selectedTask.id === 't4' && probe.selectedTarget === 1 && probe.actions.length === 0,
    '未来最后scrollBy后立刻松手，延后日期表单仍使用最新下半区插入边界');
}
console.log('19) 分组捕获可见裁片与完整业务快照');
function memberIds(members) { return members.map(member => member.task.id).join(','); }
function groupProbe() {
  const probe = floatingProbe([['a', 'A'], ['b', 'A'], ['c', 'A'], ['d', 'A'], ['e', 'A'], ['f', 'A'], ['g', 'B']], [], true);
  probe.frame('group-today-a', 100, 44, '', 45, 320);
  probe.frame('group-today-g', 260, 44, '', 45, 320);
  probe.frame('task-a', 40, 70, '', 45, 320);
  probe.frame('task-b', 130, 55, '', 45, 320);
  probe.frame('task-c', 340, 70, '', 45, 320);
  probe.frame('task-d', 380, 40, '', 45, 320);
  probe.frame('task-e', 220, 0, '', 45, 320);
  probe.frames.delete('task-f');
  probe.frame('task-g', 260, 50, '', 45, 320);
  return probe;
}
function pickGroup(probe) { probe.startFloating(gesture(100, 120), 'today', 'a', true); }
{
  const probe = groupProbe();
  pickGroup(probe);
  assert(memberIds(probe.floatingMembers) === 'a,b,c' && ids(probe.floatingTasks) === 'a,b,c,d,e,f',
    '几何只捕获当前组可见有效节点，完整业务组仍保留离屏、未布局和缺失节点成员');
  const [a, b, c] = probe.floatingMembers;
  assert(a.x === -24 && a.y === -40 && a.width === 320 && a.height === 70 && a.clipTop === 20 && a.visibleHeight === 50,
    '上边界部分可见卡准确记录根偏移、2倍密度尺寸与顶部裁片，不把隐藏内容带出List');
  assert(b.x === -24 && b.y === 30 && b.clipTop === 0 && b.visibleHeight === 55 && b.order === 2 && b.depth === 1,
    '完整可见成员保留实测高度、序号和组内层次');
  assert(c.y === 240 && c.clipTop === 0 && c.visibleHeight === 20 && c.height === 70,
    '下边界部分可见卡只捕获视口内20vp，完整卡片高度仍保留');
  assert(probe.groupMemberSource('a') && probe.groupMemberSource('c') && !probe.groupMemberSource('d') && !probe.groupMemberSource('g'),
    '只有具有可见裁片的本组源卡交给浮层，离屏和其他组卡不误隐藏');
  assert(probe.immediateAnimations === 1 && probe.immediateSnapshots[0].before.lift === 0 &&
    probe.immediateSnapshots[0].before.members.map(member => member.id).join(',') === 'a,b,c' &&
    probe.immediateSnapshots[0].after.lift === 1,
    '组员展开几何在一次同步拾起前已齐备，全部成员共用同一进度');
  const localGeometry = probe.floatingMembers.map(member => [member.x, member.y]);
  probe.moveFloating(130, 180);
  assert(probe.floatingX === 82 && probe.floatingY === 130 && JSON.stringify(probe.floatingMembers.map(member => [member.x, member.y])) === JSON.stringify(localGeometry),
    '组浮层跟手只整体平移，成员相对几何不重新测量或跳变');
  probe.frame('task-d', 180, 40, '', 500, 320);
  assert(memberIds(probe.captureGroupMembers('today', probe.floatingOriginX, probe.floatingOriginY)) === 'a,b,c',
    '横向完全移出List的卡不加入裁片');
}
{
  const probe = floatingProbe([], [['a', 'A'], ['b', 'A']], true);
  probe.frame('group-future-a', 450, 44, '', 45, 320);
  probe.frame('task-a', 550, 80, '', 45, 320);
  probe.frame('task-b', 610, 50, '', 45, 320);
  probe.tabBar(600);
  probe.startFloating(gesture(100, 470), 'future', 'a', true);
  assert(memberIds(probe.floatingMembers) === 'a' && probe.floatingMembers[0].visibleHeight === 50,
    '未来组捕获止于实测TabBar上边界，不把导航遮挡区视为可见成员');
}

console.log('20) 真实成员几何的展开、收拢与中间端点');
{
  const probe = groupProbe();
  pickGroup(probe);
  const a = probe.floatingMembers[0];
  assert(a.leftAt(0) === -24 && a.topAt(0) === -40 && a.scaleAt(0) === 1 && a.opacityAt(0) === 1,
    'progress=0精确还原源裁片位置、原比例和不透明度');
  assert(a.leftAt(1) === 10 && a.topAt(1) === 10 && a.width * a.scaleAt(1) === 252 && a.opacityAt(1) === 0,
    'progress=1进入统一摘要叠层，成员没有第二次换行布局');
  assert(a.leftAt(0.5) === -7 && a.topAt(0.5) === -15 && Math.abs(a.scaleAt(0.5) - 0.89375) < 0.00001 && a.opacityAt(0.5) === 0.5,
    '位置、比例与透明度由同一中间进度连续投影');
  assert(a.leftAt(-1) === a.leftAt(0) && a.topAt(2) === a.topAt(1) && a.scaleAt(Number.NaN) === 1,
    '弹簧越界或异常进度不会使成员反向飞出展开与收拢端点');
  const hidden = new context.ProbeGroupMember();
  hidden.width = 320; hidden.visibleHeight = 50; hidden.x = -999; hidden.y = 999; hidden.visible = false;
  assert(hidden.leftAt(0) === hidden.leftAt(1) && hidden.topAt(0) === hidden.topAt(1) && hidden.opacityAt(0) === 0,
    '目标已不可见成员停在收拢端隐藏，不展开回过期源坐标');
  const bounds = probe.floatingMembers.every(member => [0, 0.25, 0.5, 0.75, 1].every(progress =>
    Number.isFinite(member.leftAt(progress)) && Number.isFinite(member.topAt(progress)) && member.scaleAt(progress) > 0));
  assert(bounds, '不同裁片高度在整个收拢区间保持有限坐标和正比例');
}

console.log('21) 整组落位重测、可见成员交替与统一清理');
{
  const probe = groupProbe();
  pickGroup(probe);
  probe.moveFloating(100, 305);
  probe.finishFloating(true);
  assert(ids(probe.data.todayTasks) === 'g,a,b,c,d,e,f' && probe.actions.length === 1,
    '动画只捕获三张可见卡，整组六条实际任务仍完整移动且保留内部顺序');
  assert(memberIds(probe.floatingMembers) === 'a,b,c' && probe.floatingLift === 1 && probe.layoutListeners.size === 1,
    '新布局完成前保留原收拢成员集合，不使用旧布局猜目标');
  // 模拟滚动与整组重排后的最终窗口布局：之前离屏的成员进入视口，旧成员离开。
  probe.frame('group-today-a', -180, 44, '', 45, 320);
  probe.frame('task-a', -130, 70, '', 45, 320);
  probe.frame('task-b', -50, 55, '', 45, 320);
  probe.frame('task-c', 40, 70, '', 45, 320);
  probe.frame('task-d', 130, 40, '', 45, 320);
  probe.frame('task-e', 200, 50, '', 45, 320);
  probe.frame('task-f', 280, 60, '', 45, 320);
  probe.flushLayout();
  const transition = probe.immediateSnapshots.at(-1);
  assert(transition.before.lift === 1 && transition.before.members.map(member => member.id).join(',') === 'a,b,c,d,e,f' && transition.after.lift === 0,
    '新进入视口的成员先在收拢端建立，然后与旧成员进入同一次展开动画');
  assert(memberIds(probe.floatingMembers) === 'a,b,c,d,e,f' && memberIds(probe.floatingMembers.filter(member => member.visible)) === 'c,d,e,f',
    '落位沿用稳定任务ID，离屏旧成员保留隐藏节点，新目标成员得到有效展开几何');
  const c = probe.floatingMembers.find(member => member.task.id === 'c');
  assert(c.order === 4 && c.depth === 2 && c.clipTop === 20 && c.visibleHeight === 50 && probe.floatingY + c.topAt(0) + probe.floatingRootY === 60,
    '展开端点采用重排后新序号和可见裁片，窗口位置与实际目标一致');
  assert(!probe.groupMemberSource('a') && probe.groupMemberSource('d') && probe.immediateAnimations === 2 && probe.animationFinishes.length === 1,
    '源卡归属跟随新可见集合，全组只有一次拾起与一次展开完成回调');
  probe.flushLayout();
  assert(probe.immediateAnimations === 2 && probe.layoutListeners.size === 0, '后续布局不会重复启动整组展开动画');
  probe.finishAnimations();
  assert(probe.floatingPhase === 'idle' && probe.floatingMembers.length === 0 && !probe.groupMemberSource('d'),
    '展开结束一次性清理成员裁片并恢复真实列表');
}

console.log('22) 整组取消及过时布局/动画隔离');
{
  const probe = groupProbe();
  const before = JSON.stringify(probe.data);
  pickGroup(probe);
  probe.moveFloating(130, 180);
  probe.finishFloating(false);
  probe.frame('group-today-a', 120, 44, '', 45, 320);
  probe.frame('task-a', 80, 70, '', 45, 320);
  probe.flushLayout();
  const a = probe.floatingMembers.find(member => member.task.id === 'a');
  assert(probe.floatingY === 90 && probe.floatingY + a.topAt(0) + probe.floatingRootY === 80 && JSON.stringify(probe.data) === before,
    '整组取消按当前源布局展开，源区域滚动或调整后不回过时坐标');
  const oldFinish = probe.animationFinishes.shift();
  probe.resetDrag();
  probe.startFloating(gesture(100, 280), 'today', 'g', true);
  oldFinish();
  assert(probe.floatingPhase === 'lifting' && memberIds(probe.floatingMembers) === 'g' && probe.groupMemberSource('g') && probe.actions.length === 0,
    '上一组过时onFinish不能清空新组几何或提交旧业务');
  probe.finishFloating(false);
  const oldLayout = probe.landingLayout;
  probe.resetDrag();
  oldLayout();
  assert(probe.floatingPhase === 'idle' && probe.floatingMembers.length === 0 && probe.layoutListeners.size === 0 && probe.animationFinishes.length === 0,
    '页面隐藏注销整组布局监听，滞后回调不会重新生成成员或动画');
}
console.log('23) 整组移到首位归零，其他落点保留滚动位置');
{
  const cases = [];
  for (const section of ['today', 'future']) {
    for (const target of ['B', null]) {
      const list = [['a', target === null ? 'A' : null], ['b', target]];
      const other = [['keep', 'KEEP']];
      const probe = createProbe(section === 'today' ? list : other, section === 'future' ? list : other, true);
      probe.offsets.today = 90; probe.offsets.future = 130;
      probe.beginGroupDrag(target, section);
      probe.previewDrop(section, 0, list[0][1]);
      probe.finishDrop(event(), section);
      cases.push({ section, target, probe });
    }
  }
  assert(cases.filter(item => item.target === 'B').every(({ section, probe }) =>
    ids(probe.tasks(section)) === 'b,a' && probe.offsets[section] === 0),
    '命名组在当日或未来移到首位，真实排序后均将该列表归零');
  assert(cases.filter(item => item.target === null).every(({ section, probe }) =>
    ids(probe.tasks(section)) === 'b,a' && probe.offsets[section] === 0),
    '未分组同样适用首位归零，不因group=null漏掉标题对齐');
  assert(cases.every(({ section, probe }) => {
    const call = probe.scrollTos[0];
    return probe.scrollTos.length === 1 && call.section === section && call.xOffset === 0 && call.yOffset === 0 &&
      call.animation === false && call.actionsAtCall === 1 && probe.offsets[section === 'today' ? 'future' : 'today'] === (section === 'today' ? 130 : 90);
  }), '先提交整组排序，再无动画归零当前分区一次，不影响另一分区');
}
{
  const cases = [2, 3].map(boundary => {
    const probe = createProbe([['a', 'A'], ['b', 'B'], ['c', 'C']], [], true);
    probe.offsets.today = 87;
    probe.beginGroupDrag('A', 'today');
    probe.previewDrop('today', boundary, boundary === 2 ? 'B' : 'C');
    probe.finishDrop(event(), 'today');
    return probe;
  });
  assert(ids(cases[0].data.todayTasks) === 'b,a,c' && ids(cases[1].data.todayTasks) === 'b,c,a' &&
    cases.every(probe => probe.offsets.today === 87 && probe.scrollTos.length === 0),
    '整组移动到中间或末尾保留原滚动位置，不扩大归零条件');
}
{
  const probe = createProbe([['a', 'A'], ['b', 'B']], [['f', 'F']], true);
  const before = JSON.stringify(probe.data);
  probe.beginGroupDrag('B', 'today');
  probe.previewDrop('today', 0, 'A');
  probe.finishDrop(event(), 'future');
  assert(probe.offsets.today === 200 && probe.offsets.future === 200 && probe.scrollTos.length === 0 && JSON.stringify(probe.data) === before,
    '非法整组跨区取消不会借用旧首位落点重置任何列表');
}
{
  const probe = groupProbe();
  const before = JSON.stringify(probe.data);
  pickGroup(probe);
  probe.previewDrop('today', 0, 'A');
  probe.finishFloating(false);
  probe.flushLayout(); probe.finishAnimations();
  assert(probe.offsets.today === 200 && probe.offsets.future === 200 && probe.scrollTos.length === 0 && JSON.stringify(probe.data) === before,
    '取消首位预览仅展开回源，不归零也不提交排序');
}
{
  const probe = createProbe(['a', 'b']);
  begin(probe, 'b');
  probe.previewDrop('today', 0, null);
  probe.finishDrop(event(), 'today');
  assert(ids(probe.data.todayTasks) === 'b,a' && probe.offsets.today === 200 && probe.scrollTos.length === 0,
    '单卡移到首位仍保持原行为，不触发整组标题归零');
}
{
  const probe = floatingProbe([['a', 'A'], ['b', 'B']], [], true);
  probe.offsets.today = 100;
  probe.frame('group-today-b', 260, 44, 'today', 45, 320);
  probe.frame('task-a', 180, 50, 'today', 45, 320);
  probe.frame('task-b', 320, 50, 'today', 45, 320);
  probe.startFloating(gesture(100, 180), 'today', 'b', true);
  probe.moveFloating(100, 100);
  probe.finishFloating(true);
  assert(ids(probe.data.todayTasks) === 'b,a' && probe.offsets.today === 0 && probe.floatingPhase === 'settling' &&
    probe.immediateAnimations === 1 && probe.layoutListeners.size === 1,
    '首位提交已归零后才等待didLayout，展开尚未使用旧滚动几何');
  probe.frame('group-today-b', 90, 44, 'today', 45, 320);
  probe.frame('task-b', 142, 50, 'today', 45, 320);
  probe.flushLayout();
  const member = probe.floatingMembers.find(item => item.task.id === 'b');
  assert(probe.floatingY === 60 && member.order === 1 && probe.floatingY + member.topAt(0) + probe.floatingRootY === 142 &&
    probe.scrollTos.length === 1,
    '展开捕获归零后的标题与成员窗口位置，不再把残留offset带入组首间距');
}
console.log('24) 下方提示只依据真实任务下溢');
function hintProbe(today = ['a', 'b'], future = ['f']) {
  const probe = createProbe(today, future);
  probe.ready = true;
  probe.frame('list-today', 100, 200);
  probe.frame('list-future', 420, 260);
  probe.tabBar(600);
  return probe;
}
{
  const probe = hintProbe([], []);
  probe.itemRect('today', 0, 250, 700);
  probe.itemRect('future', 0, 250, 700);
  assert(!probe.moreTasksBelow('today') && !probe.moreTasksBelow('future') && probe.rectReads.length === 0,
    '空列表即使添加区或尾部很高也不显示还有日程，且不查询无效任务索引');
}
{
  const probe = hintProbe();
  probe.itemRect('today', 1, 140, 50);
  probe.itemRect('today', 2, 200, 800);
  probe.itemRect('future', 0, 120, 40);
  probe.itemRect('future', 1, 170, 800);
  probe.futureTailSpace = 1000;
  assert(!probe.todayScroller.isAtEnd() && !probe.moreTasksBelow('today') && !probe.moreTasksBelow('future') &&
    probe.rectReads.every(([section, index]) => index === (section === 'today' ? 1 : 0)),
    '末任务已完整可见时不受footer、Blank或isAtEnd=false误导，只查询最后真实任务');
  probe.itemRect('today', 1, 180, 50);
  assert(probe.moreTasksBelow('today'), '末任务下半卡超出List底部时提示，不要求整项离屏');
  probe.itemRect('today', 1, 180, 20.8);
  const withinTolerance = probe.moreTasksBelow('today');
  probe.itemRect('today', 1, 180, 21.2);
  assert(!withinTolerance && probe.moreTasksBelow('today'), 'List相对矩形按vp直接计算，1vp容差避免亚像素闪烁');
  probe.itemRect('today', 1, -80, 40);
  assert(!probe.moreTasksBelow('today'), '只有任务位于当前视口上方时不误报下方内容');
}
{
  const probe = hintProbe();
  probe.itemRect('future', 0, 170, 50);
  assert(probe.moreTasksBelow('future'), '未来末卡虽在物理List内，但超过TabBar有效边界仍显示提示');
  probe.itemRect('future', 0, 120, 50);
  assert(!probe.moreTasksBelow('future'), '滚动后未来末卡完整到达浮栏上方时提示消失');
}

console.log('25) 离屏零矩形、可见索引与未知布局回退');
{
  const probe = hintProbe(['a', 'b', 'c'], ['f', 'g', 'h']);
  probe.recordVisibleItems('today', 0, 1);
  assert(probe.todayMoreBelow && !probe.futureMoreBelow && probe.todayFirstVisible === 0 &&
    probe.todayLastVisible === 1 && probe.futureLastVisible === -1,
    '末任务离屏返回零矩形时，用最后可见索引判断还有任务且不串改另一分区索引');
  probe.itemRect('today', 2, 100, 50);
  assert(!probe.moreTasksBelow('today'), '有效末任务几何优先于暂时落后的可见索引');
  probe.rectMaps.today.clear();
  probe.recordVisibleItems('today', 3, 3);
  assert(!probe.todayMoreBelow, '仅尾部ListItem可见时，末任务已在上方，不把尾部当待显示任务');
  probe.recordVisibleItems('future', 0, 1);
  assert(probe.futureMoreBelow && !probe.todayMoreBelow && probe.todayFirstVisible === 3,
    '未来列表也独立使用任务索引兜底，不重置当日判断');
}
{
  const probe = hintProbe();
  probe.todayMoreBelow = true;
  const retained = probe.moreTasksBelow('today');
  probe.todayMoreBelow = false;
  assert(retained && !probe.moreTasksBelow('today'), '无有效矩形或索引时保留原状态，不把未知当作到底');
  probe.bound = false;
  probe.todayFirstVisible = 0; probe.todayLastVisible = 0;
  assert(probe.moreTasksBelow('today'), 'Scroller未绑定抛100004时安全回退索引，不使布局回调崩溃');
  probe.todayMoreBelow = true;
  probe.frames.delete('list-today');
  assert(!probe.moreTasksBelow('today'), '列表几何不存在时隐藏提示，不沿用过时状态');
}

console.log('26) 两区提示、避让距离与状态去重');
{
  const probe = hintProbe();
  probe.itemRect('today', 1, 180, 50);
  probe.itemRect('future', 0, 120, 40);
  probe.updateMoreBelow();
  assert(probe.todayMoreBelow && !probe.futureMoreBelow && probe.futureMoreInset === 80 && probe.animationCalls === 1,
    '一次更新独立计算两区并在同一次动画写入变化，未来提示避开实测80vp遮挡');
  probe.futureTailSpace = 2000;
  probe.updateMoreBelow(); probe.updateMoreBelow();
  assert(probe.animationCalls === 1, '相同布局和仅footer变化不会重复启动提示动画');
  let writes = 0;
  let inset = probe.futureMoreInset;
  Object.defineProperty(probe, 'futureMoreInset', { get: () => inset, set: value => { inset = value; writes++; } });
  probe.tabBar(600.3);
  probe.updateMoreBelow();
  probe.tabBar(598);
  probe.updateMoreBelow();
  assert(writes === 1 && inset === 82 && probe.animationCalls === 1,
    '避让距离小于0.5vp的抖动不写状态，真实变化更新但不重开无关提示动画');
  probe.tabBar(400);
  probe.updateMoreBelow();
  assert(probe.futureMoreInset === 260 && !probe.futureMoreBelow, '底栏完全覆盖列表时避让量限制到List高度，提示不落到无效区域');
  probe.floatingPhase = 'lifting';
  const lifting = probe.moreHintVisible('today');
  probe.floatingPhase = 'dragging';
  const dragging = probe.moreHintVisible('today');
  probe.floatingPhase = 'settling';
  const settling = probe.moreHintVisible('today');
  probe.floatingPhase = 'idle';
  assert(!lifting && !dragging && !settling && probe.moreHintVisible('today') && probe.todayMoreBelow,
    '拾起、跟手及落位期间暂隐提示，结束后恢复真实下溢状态');
  probe.page = 1;
  probe.updateMoreBelow();
  assert(!probe.todayMoreBelow && !probe.futureMoreBelow && probe.futureMoreInset === 0,
    '切到非主页后隐藏两区提示并清掉避让距离');
  probe.page = 0; probe.ready = false;
  probe.rectReads.length = 0;
  probe.updateMoreBelow();
  assert(!probe.todayMoreBelow && !probe.futureMoreBelow && probe.rectReads.length === 0,
    '数据未就绪时不读取Scroller，也不显示过时提示');
}
{
  const probe = hintProbe(['a'], []);
  probe.itemRect('today', 0, 180, 50);
  probe.updateMoreBelow();
  probe.frame('list-today', 100, 240);
  probe.updateMoreBelow();
  assert(!probe.todayMoreBelow, '分隔条扩大任务可见区后，布局更新立即取消已不需要的提示');
  probe.frame('list-today', 100, 200);
  probe.updateMoreBelow();
  const action = new AppAction('DELETE_TASK'); action.id = 'a';
  probe.dispatch(action);
  probe.updateMoreBelow();
  assert(probe.data.todayTasks.length === 0 && !probe.todayMoreBelow,
    '真实删除最后任务后清除旧提示，不受缓存下溢矩形影响');
}

console.log('27) 下方提示布局观察与其他监听隔离');
{
  const probe = hintProbe();
  probe.itemRect('today', 1, 180, 50);
  let unrelated = 0;
  const otherListener = () => { unrelated++; };
  probe.layoutListeners.add(otherListener);
  probe.startMoreObservation(); probe.startMoreObservation();
  assert(probe.layoutListeners.size === 2 && typeof probe.moreLayout === 'function',
    '重复注册提示观察仍只有一个自己的didLayout监听，不清除其他布局用途');
  probe.flushLayout();
  assert(probe.todayMoreBelow && unrelated === 1, 'didLayout执行真实提示计算，并保留其他监听回调');
  probe.stopMoreObservation();
  probe.itemRect('today', 1, 100, 40);
  probe.flushLayout();
  assert(probe.moreLayout === undefined && probe.layoutListeners.size === 1 && unrelated === 2 && probe.todayMoreBelow,
    '停止观察只注销提示自己的回调，后续布局不会再更新已卸载提示');
}
console.log(`Index drag regression: ${passed} assertions passed (including 240 boundary combinations).`);
