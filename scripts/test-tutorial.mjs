// 执行真实简要说明配置与 Preferences 服务，验证首次显示、确认和异步保存。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
const project = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
let ts;
for (const candidate of [process.env.TYPESCRIPT_PATH, 'typescript', path.join(project, '../Planer/node_modules/typescript'),
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'].filter(Boolean)) {
  try { ts = require(candidate); break; } catch {}
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向已有 TypeScript。');
let disk = '';
let cache = '';
let failRead = false;
let failWrite = false;
let failFlush = false;
const writes = [];
const preferences = {
  getPreferences: async (_context, options) => {
    if (options.name !== 'planer_tutorial') throw new Error('存储名称错误');
    if (failRead) throw new Error('模拟读取失败');
    return {
      get: async () => disk,
      put: async (key, value) => {
        if (key !== 'progress') throw new Error('进度键错误');
        if (failWrite) { failWrite = false; throw new Error('模拟写入失败'); }
        cache = value; writes.push(JSON.parse(value).status);
      },
      flush: async () => {
        await new Promise(resolve => setTimeout(resolve, 2));
        if (failFlush) { failFlush = false; throw new Error('模拟落盘失败'); }
        disk = cache;
      }
    };
  }
};
const modules = new Map();
function load(relative) {
  const filename = path.join(project, 'entry/src/main/ets', relative + '.ets');
  if (modules.has(filename)) return modules.get(filename);
  const source = readFileSync(filename, 'utf8');
  const result = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } });
  const module = { exports: {} };
  vm.runInThisContext(`(function(require,module,exports){${result.outputText}\n})`, { filename })(request => {
    if (request === '@kit.ArkData') return { preferences };
    return load(path.join(path.dirname(relative), request));
  }, module, module.exports);
  modules.set(filename, module.exports);
  return module.exports;
}
const { TutorialProgress, tutorialFeatures, TUTORIAL_VERSION,
  normalizeTutorial, shouldAutoTutorial, closeTutorial, TUTORIAL_FOOTNOTE } = load('tutorial/TutorialConfig');
const { TutorialStorage } = load('services/TutorialStorage');
let passed = 0;
function assert(condition, label) { if (!condition) throw new Error(label); passed++; console.log('✓ ' + label); }
async function rejects(promise) { try { await promise; return false; } catch { return true; } }
const features = tutorialFeatures();
assert(features.length === 8 && new Set(features.map(item=>item.id)).size === features.length, '核心说明含八项且ID唯一');
assert(features.every(item=>item.title && item.description && item.icon), '每项说明保留简短标题、内容和图标');
const iconSource = readFileSync(path.join(project, 'entry/src/main/ets/components/PlanerIcon.ets'), 'utf8');
const iconMethods = ['usesSymbol', 'symbolSource', 'mediaSource'].map(name => {
  const match = iconSource.match(new RegExp('  private ' + name + '\\([^]*?\\n  \\}', 'm'));
  if (!match) throw new Error('图标映射方法未找到：' + name);
  return match[0];
}).join('\n');
const iconExports = {};
vm.runInNewContext(ts.transpileModule(`class Icon { ${iconMethods} }; exports.Icon=Icon;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText, { exports: iconExports, $r: name => name });
const checkInIcon = new iconExports.Icon(); checkInIcon.icon = features.find(item => item.id === 'checkin').icon;
const groupIcon = new iconExports.Icon(); groupIcon.icon = features.find(item => item.id === 'group').icon;
assert(checkInIcon.usesSymbol() && groupIcon.usesSymbol() && checkInIcon.symbolSource() === 'sys.symbol.checkmark' && groupIcon.symbolSource() === 'sys.symbol.folder', '教程打卡与分组使用不同且语义明确的系统符号');
function resolvedIcon(name) {
  const icon = new iconExports.Icon(); icon.icon = name; icon.filled = false;
  return icon.usesSymbol() ? icon.symbolSource() : icon.mediaSource();
}
assert(new Set(features.map(feature => resolvedIcon(feature.icon))).size === features.length,
  '全部八项教程映射到不同资源，不只比较图标别名');
assert(resolvedIcon(features.find(item => item.id === 'group').icon) !== resolvedIcon(features.find(item => item.id === 'widget').icon),
  '分组文件夹与桌面卡片网格不会解析到同一个图标');
assert(resolvedIcon(features.find(item => item.id === 'checkin-increment').icon) === 'sys.symbol.arrow_right_circle',
  '内容接续使用前进符号，与安排日期的日历区分');
assert(resolvedIcon('pause') === 'sys.symbol.pause' && resolvedIcon('play') === 'sys.symbol.play_fill' &&
  resolvedIcon('paused') === 'sys.symbol.pause_circle_fill', '暂停操作、继续操作和已暂停状态使用不同系统符号');
assert(features.some(item => item.id === 'widget' && item.description.includes('三种尺寸')), '教程包含桌面组件尺寸与操作说明');
assert(features.some(item => item.id === 'checkin' && item.description.includes('补卡') && item.description.includes('同步到日程')), '教程说明打卡入口、日程联动与补卡');
assert(features.some(item => item.id === 'checkin-increment' && item.description.includes('1-10') && item.description.includes('第10节') && item.description.includes('点提示开启')), '教程用区间和单编号示例说明一键开启递增');
assert(shouldAutoTutorial({version: TUTORIAL_VERSION - 1, status: 'completed'}), '新增打卡说明升级版本后展示一次新版教程');
assert(!TUTORIAL_FOOTNOTE.includes('自动保存'), '教程底部不再显示本机自动保存');
features.pop();
assert(tutorialFeatures().length === 8, '读取配置不允许外部增删污染原列表');
const fresh = new TutorialProgress();
assert(shouldAutoTutorial(fresh), '首次启动显示一页说明');
const closed = closeTutorial(fresh);
assert(closed.status === 'completed' && fresh.status === 'new', '关闭或开始使用记住确认状态，原快照不变');
assert(!shouldAutoTutorial(closed), '确认后后续启动不反复显示');
assert(normalizeTutorial({version:TUTORIAL_VERSION - 1,status:'inProgress',stepId:'future-text'}).status === 'new', '旧长教程迁移到简要说明，不恢复旧步骤');
assert(normalizeTutorial(null).status === 'new' && normalizeTutorial({version:TUTORIAL_VERSION,status:'invalid'}).status === 'new', '空值和非法状态安全回退');
assert(Object.keys(normalizeTutorial({...closed,todayId:'old',futureId:'old',stepId:'old'})).sort().join(',') === 'status,version', '持久状态不再绑定日程或逐步引导');
const store = new TutorialStorage();
assert(await rejects(store.save(closed)), '未读取成功前不写入状态');
assert((await store.load({})).status === 'new' && disk === '', '首次读取不提前标记已看');
await store.save(closed);
assert((await new TutorialStorage().load({})).status === 'completed', '重新创建服务后仍记住确认，避免重启重复提示');
const snapshot = new TutorialProgress();
const first = store.save(snapshot);
snapshot.status = 'completed';
const second = store.save(closed);
await Promise.all([first,second]);
assert(writes.slice(-2).join(',') === 'new,completed', '保存时立即取快照，并按顺序落盘');
assert(JSON.parse(disk).status === 'completed', '旧异步写入不覆盖最新确认');
failWrite = true;
assert(await rejects(store.save(fresh)), '写入失败明确反馈');
await store.save(closed);
assert(JSON.parse(disk).status === 'completed', '一次写入失败不阻断重试');
failFlush = true;
assert(await rejects(store.save(fresh)), '落盘失败不冒充已记住');
await store.save(closed);
assert((await store.load({})).status === 'completed', '重试落盘后可正确恢复');
failRead = true;
const blocked = new TutorialStorage();
assert(await rejects(blocked.load({})) && await rejects(blocked.save(closed)), '读取失败不绑定可写存储');
failRead = false;
disk = '{broken';
assert((await blocked.load({})).status === 'new', '损坏的教程标记不影响日程数据读取');
const indexSource = readFileSync(path.join(project, 'entry/src/main/ets/pages/Index.ets'), 'utf8');
const methods = ['openTutorial', 'dismissTutorial', 'completeTutorial', 'tutorialContentReady'].map(name => {
  const match = indexSource.match(new RegExp('^  private ' + name + '\\([^]*?\\n  \\}', 'm'));
  if (!match) throw new Error('教程生命周期方法未找到：' + name);
  return match[0];
}).join('\n');
const pageExports = {};
const compiled = ts.transpileModule(`class Page { ${methods} }; exports.Page=Page;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
const frames = [];
vm.runInNewContext(compiled, { exports: pageExports, closeTutorial,
  TutorialEntranceFrame: class { constructor(callback) { this.callback = callback; } } });
const page = new pageExports.Page();
page.tutorialLoading = false; page.tutorialShown = false; page.tutorialProgress = new TutorialProgress();
page.getUIContext = () => ({ postFrameCallback: frame => { frames.push(frame.callback); } });
page.tutorialEntranceRevision = 0; page.tutorialDisposed = false;
page.resetDrag = () => {}; page.saved = 0; page.saveTutorial = () => { page.saved++; };
page.openTutorial();
assert(page.tutorialShown && !page.tutorialEntered, '打开面板时条目保留初始位置，等首帧即可开始');
page.tutorialContentReady(); frames.shift()();
assert(page.tutorialEntered, '正文首帧即开始条目动画，不等待面板上升结束');
page.dismissTutorial(); page.completeTutorial();
assert(!page.tutorialShown && page.saved === 1 && page.tutorialProgress.status === 'completed', '按钮与面板消失回调共用幂等关闭标记');
page.openTutorial(); page.dismissTutorial();
assert(page.saved === 1, '设置回看关闭不重复覆盖首次使用标记');
page.openTutorial(); page.tutorialContentReady(); page.dismissTutorial(); frames.shift()();
assert(!page.tutorialEntered, '关闭面板后过期首帧不会重新触发条目动画');
console.log(`Tutorial regression: ${passed} assertions passed.`);
