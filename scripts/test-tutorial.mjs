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
  normalizeTutorial, shouldAutoTutorial, closeTutorial } = load('tutorial/TutorialConfig');
const { TutorialStorage } = load('services/TutorialStorage');
let passed = 0;
function assert(condition, label) { if (!condition) throw new Error(label); passed++; console.log('✓ ' + label); }
async function rejects(promise) { try { await promise; return false; } catch { return true; } }
const features = tutorialFeatures();
assert(features.length === 5 && new Set(features.map(item=>item.id)).size === features.length, '核心说明精简为五项且ID唯一');
assert(features.every(item=>item.title && item.description && item.icon), '每项说明保留简短标题、内容和图标');
features.pop();
assert(tutorialFeatures().length === 5, '读取配置不允许外部增删污染原列表');
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
console.log(`Tutorial regression: ${passed} assertions passed.`);
