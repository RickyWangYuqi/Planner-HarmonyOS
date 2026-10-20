// 在内存文件系统中执行真实 PlanerStorage ArkTS，验证保存契约；不能替代设备文件系统测试。
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
  try { ts = require(candidate); break; } catch { /* 使用现有工具链，不下载依赖。 */ }
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向现有 TypeScript 模块。');
const files = new Map();
const descriptors = new Map();
let nextDescriptor = 1;
let failWrite = false;
let shortWrite = false;
const fileIo = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  access: async name => files.has(name),
  open: async name => {
    const file = { fd: nextDescriptor++ };
    files.set(name, '');
    descriptors.set(file.fd, name);
    return file;
  },
  write: async (descriptor, text) => {
    if (failWrite) { failWrite = false; throw new Error('模拟磁盘写入失败'); }
    const value = shortWrite ? text.slice(0, 10) : text;
    shortWrite = false;
    files.set(descriptors.get(descriptor), value);
    return Buffer.byteLength(value);
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
const { PlanerStorage } = load('services/PlanerStorage');
const { AppData, Task } = load('model/PlanerModel');
const { freshData } = load('model/PlanerEngine');
const context = { filesDir: '/mock-sandbox' };
const dataPath = context.filesDir + '/data.json';
let passed = 0;
function assert(condition, message) {
  if (!condition) throw new Error(message);
  passed++;
  console.log(`✓ ${message}`);
}
async function failed(promise) {
  try { await promise; return false; } catch { return true; }
}
const storage = new PlanerStorage();
const initial = await storage.load(context);
assert(initial instanceof AppData, '首次加载返回有效 AppData 实例');
assert(files.size === 0, '首次加载不创建或改写任何数据文件');
await storage.save(context, initial);
assert(files.has(dataPath) && !files.has(dataPath + '.tmp'), '完整保存后原子替换主文件');
assert(!files.has(dataPath + '.bak'), '首次保存不虚构上一版备份');
const first = initial.clone();
const task = new Task();
task.id = 'one';
task.text = '第一版';
first.todayTasks.push(task);
const firstSave = storage.save(context, first);
first.todayTasks[0].text = '调用后修改';
const second = first.clone();
second.todayTasks[0].text = '最终版';
const secondSave = storage.save(context, second);
await Promise.all([firstSave, secondSave]);
assert(JSON.parse(files.get(dataPath)).todayTasks[0].text === '最终版', '连续保存按调用次序提交最新数据');
assert(JSON.parse(files.get(dataPath + '.bak')).todayTasks[0].text === '第一版', '备份保留调用时固定的前一版快照');
const roundTrip = await storage.load(context);
assert(roundTrip.todayTasks[0] instanceof Task && roundTrip.settings.clone(), '重读后还原模型实例方法');
const correctText = files.get(dataPath);
files.set(dataPath, '{ broken json');
assert(await failed(storage.load(context)), '坏 JSON 明确报告读取失败');
assert(await failed(storage.save(context, initial)), '读取失败后禁止覆盖原文件');
assert(files.get(dataPath) === '{ broken json', '坏 JSON 原文件保持不变');
files.delete(dataPath);
assert(await failed(storage.load(context)), '发现孤立备份时不当作空白首次启动');
files.set(dataPath, correctText);
await storage.load(context);
failWrite = true;
assert(await failed(storage.save(context, freshData())), '写入失败返回可处理错误');
assert(files.get(dataPath) === correctText, '写入失败保留完整旧主文件');
await storage.save(context, roundTrip);
assert(files.get(dataPath) === JSON.stringify(roundTrip), '一次写入失败后后续保存仍可恢复');
shortWrite = true;
assert(await failed(storage.save(context, freshData())), '写入不完整时拒绝提交主文件');
assert(files.get(dataPath) === JSON.stringify(roundTrip), '短写保持旧主文件不变');
assert(await failed(new PlanerStorage().save(context, freshData())), '未加载实例禁止保存');
assert(descriptors.size === 0, '成功与失败路径均关闭文件描述符');
console.log(`存储契约：${passed} 项通过（内存 mock，未运行设备 API）。`);
