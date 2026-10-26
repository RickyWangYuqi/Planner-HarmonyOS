// 执行真实打卡表单方法与真实领域引擎，检查分组草稿、保存及外部变化；不访问用户数据。
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
const project = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
let ts;
for (const location of [process.env.TYPESCRIPT_PATH, 'typescript', path.join(project, '../Planer/node_modules/typescript'),
  'D:/Software/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'].filter(Boolean)) {
  try { ts = require(location); break; } catch {}
}
if (!ts) throw new Error('请设置 TYPESCRIPT_PATH 指向已有 TypeScript 模块。');
function transpile(source, filename) {
  const result = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, reportDiagnostics: true, fileName: filename });
  const errors = (result.diagnostics || []).filter(value => value.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(errors.map(value => value.messageText).join('\n'));
  return result.outputText;
}
const models = new Map();
function load(name) {
  if (models.has(name)) return models.get(name);
  const filename = path.join(project, 'entry/src/main/ets/model', name + '.ets');
  const module = { exports: {} };
  models.set(name, module.exports);
  vm.runInThisContext('(function(require,module,exports){' + transpile(readFileSync(filename, 'utf8'), filename) + '\n})')(
    request => load(path.basename(request)), module, module.exports);
  return module.exports;
}
const model = load('PlanerModel'), checkInModel = load('CheckInModel'), engine = load('PlanerEngine'), checkInEngine = load('CheckInEngine');
const source = readFileSync(path.join(project, 'entry/src/main/ets/components/CheckInEditor.ets'), 'utf8');
const start = source.indexOf('@Component'), end = source.indexOf('  @Builder', start);
function builder(name) {
  const i = source.indexOf('@Builder private ' + name + '(');
  if (i < 0) throw new Error('缺少真实Builder：' + name);
  const j = source.indexOf('@Builder', i + 1);
  return source.slice(i, j < 0 ? undefined : j);
}
const chipColor = builder('groupLabelButton').match(/\.fontColor\(([^\n]+)\)/)[1];
const chipModifier = builder('groupLabelButton').match(/\.attributeModifier\(([^\n]+)\)/)[1];
const visible = source.match(/if \((this\.data\.settings\.showGroups)\) \{\s*MaterialSection\([^\n]+this\.groupSectionBody/)[1];
const cls = source.slice(start, end).replace('@Component', '').replace('export struct CheckInEditor', 'class CheckInEditor')
  .replace(/@(?:Prop|State)\s+/g, '') + `
  getUIContext() { return { animateTo: (options, fn) => { this.animations++; fn(); options.onFinish?.(); }, getPromptAction: () => ({showToast() {}}) }; }
  colorFromView(group) { return ${chipColor}; }
  modifierFromView(group) { return ${chipModifier}; }
  groupVisibleFromView() { return ${visible}; }
}\nglobalThis.Editor = CheckInEditor;`;
const context = vm.createContext({ ...model, ...checkInModel, ...engine, ...checkInEngine,
  Palette: class {}, Scroller: class {}, Motion: { quick: () => ({}), spring: () => ({}) },
  EditorMaterialRefresh: { request() {} }, PlanerControlModifier: class { constructor(palette, selected, danger, border, style) { this.selected = selected; this.danger = danger; this.border = border; this.style = style; } },
  BorderStyle: { Solid: 'solid' } });
vm.runInContext(transpile(cls, 'CheckInEditor.ets'), context);
let passed = 0;
function assert(condition, message) { if (!condition) throw new Error(message); passed++; console.log('✓ ' + message); }
function fresh() {
  const data = new model.AppData(); data.currentDate = data.lastRolloverDate = '2026-10-27';
  data.settings.showGroups = true; data.groups = ['学习', '生活']; return data;
}
function make(data = fresh(), item = new checkInModel.CheckInItem()) {
  const editor = new context.Editor(); editor.animations = 0; editor.saved = [];
  editor.data = data; editor.item = item; editor.palette = { accent: 'accent', textSoft: 'soft' };
  editor.onSave = candidate => {
    const action = Object.assign(new model.AppAction('CHECKIN_SAVE'), { checkIn: candidate });
    const error = checkInEngine.validateCheckInAction(editor.data, action);
    if (error) return error;
    editor.data = engine.reduce(editor.data, action); editor.saved.push(candidate); return '';
  };
  editor.aboutToAppear(); editor.startDate = '2026-10-27';
  return editor;
}
const form = make();
assert(form.currentGroup() === '' && form.groupVisibleFromView(), '新计划默认未分组，开启分组显示时表单可见');
assert(form.groups().join(',') === '学习,生活', '读取日程共享分组目录');
form.pickGroup('学习');
assert(form.currentGroup() === '学习' && form.candidate().group === '学习', '选择已有分组进入候选计划');
assert(form.colorFromView('学习') === 'accent' && form.modifierFromView('学习').selected, '同一标签真实文字与材质表达式同步选中状态');
form.pickGroup('学习');
assert(form.currentGroup() === '' && form.colorFromView('学习') === 'soft' && !form.modifierFromView('学习').selected, '再次点击取消选中并恢复普通材质');
form.pickGroup('生活'); form.openGroupForm(); form.groupName = '  阅读  '; form.createGroup();
assert(form.currentGroup() === '阅读' && !form.creatingGroup && form.groupName === '', '创建并选中去除空白，收起输入区');
assert(form.groups().includes('阅读') && !form.data.groups.includes('阅读') && form.data.checkIns.length === 0, '新组只在当前草稿可见，不提前保存');
form.openGroupForm(); form.groupName = '阅读'; form.createGroup();
assert(form.groups().filter(value => value === '阅读').length === 1, '同名草稿分组复用，不产生重复标签');
form.openGroupForm(); form.groupName = '学习'; form.createGroup();
assert(form.currentGroup() === '学习' && form.draftGroups.length === 1, '同名已保存组直接选用，不增加草稿');
form.openGroupForm(); form.groupName = '不保存'; form.cancelGroupForm();
assert(!form.creatingGroup && form.groupName === '' && form.currentGroup() === '学习' && !form.groups().includes('不保存'), '取消创建清除输入且保留已选组');
form.openGroupForm(); form.groupName = '   '; form.createGroup();
assert(form.creatingGroup && form.currentGroup() === '学习', '空白创建不会清空原选择');
form.cancelGroupForm();
const abandoned = make(); abandoned.openGroupForm(); abandoned.groupName = '取消整页'; abandoned.createGroup(); abandoned.aboutToDisappear();
assert(!abandoned.data.groups.includes('取消整页') && abandoned.data.checkIns.length === 0, '关闭整张表单不保存计划或草稿分组');
form.name = '看网课第1节'; form.openGroupForm(); form.groupName = '  运动  '; form.save();
assert(form.saved.length === 1 && form.data.groups.includes('运动') && !form.data.groups.includes('阅读'), '直接主保存原子提交当前输入组，不提交未采用的草稿');
assert(form.data.checkIns[0].group === '运动' && form.data.todayTasks[0].group === '运动', '新计划与实际生成日程使用所选分组');
const invalid = make(); invalid.openGroupForm(); invalid.groupName = '无效计划组'; invalid.save();
assert(!!invalid.error && invalid.saved.length === 0 && !invalid.data.groups.includes('无效计划组'), '计划校验失败时不泄漏新组到全局目录');
invalid.name = '读书'; invalid.save();
assert(invalid.saved.length === 1 && invalid.data.groups.includes('无效计划组'), '修正输入后保存沿用分组草稿');
const existing = form.data.checkIns[0].clone();
const edit = make(form.data, existing);
assert(edit.currentGroup() === '运动' && edit.candidate().group === '运动', '编辑已选分组正确回填');
edit.pickGroup('生活'); edit.save();
assert(edit.data.checkIns[0].group === '生活' && edit.data.todayTasks[0].group === '生活', '编辑更换分组同步当期日程');
const external = make(edit.data, edit.data.checkIns[0].clone());
external.data = engine.reduce(external.data, Object.assign(new model.AppAction('DELETE_GROUP'), { group: '生活', section: 'today' }));
assert(external.currentGroup() === '' && external.candidate().group === '' && !external.groups().includes('生活'), '外部删除分组后，未手改的打开表单跟随清除');
external.save();
assert(!external.data.groups.includes('生活') && external.data.checkIns[0].group === '', '保存旧表单不会复活外部删除的分组');
const hidden = make(edit.data, edit.data.checkIns[0].clone()); hidden.pickGroup('学习'); hidden.data.settings.showGroups = false;
assert(!hidden.groupVisibleFromView() && hidden.candidate().group === '生活', '关闭分组显示隐藏分区并保留当前计划归属，不提交隐藏选择');
const hiddenNew = make(); hiddenNew.data.settings.showGroups = false; hiddenNew.name = '走路'; hiddenNew.creatingGroup = true; hiddenNew.groupName = '隐藏草稿'; hiddenNew.save();
assert(hiddenNew.data.checkIns[0].group === '' && !hiddenNew.data.groups.includes('隐藏草稿'), '关闭分组时主保存不创建隐藏草稿');
const failure = make(); failure.name = '失败重试'; failure.openGroupForm(); failure.groupName = '本地草稿'; failure.onSave = () => '保存失败'; failure.save();
assert(failure.error === '保存失败' && failure.currentGroup() === '本地草稿' && !failure.data.groups.includes('本地草稿'), '保存失败保留可重试选择且不污染全局');
assert(form.animations > 0 && invalid.animations > 0, '分组选择及表单展开收起通过既有布局动画与材质刷新');
console.log(`\n打卡分组表单回归：${passed} 项断言通过。`);
